#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "find"
require "json"
require "pathname"
require "rubygems/package"
require "tempfile"

def fail_with(message)
  warn(message)
  exit(1)
end

def sha256(data)
  Digest::SHA256.hexdigest(data)
end

def normalize_notice_text(data, path)
  text = data.dup.force_encoding(Encoding::UTF_8)
  fail_with("Notice text is not valid UTF-8: #{path}") unless text.valid_encoding?
  text.gsub(/\r\n?/, "\n").gsub(/[ \t]+(?=\n|\z)/, "")
end

def write_atomic(path, data)
  directory = File.dirname(path)
  FileUtils.mkdir_p(directory)
  temporary = File.join(directory, ".#{File.basename(path)}.#{Process.pid}.tmp")
  File.binwrite(temporary, data)
  File.chmod(0o644, temporary)
  File.rename(temporary, path)
ensure
  File.delete(temporary) if defined?(temporary) && File.exist?(temporary)
end

def parse_metadata(path)
  data = File.binread(path).force_encoding(Encoding::UTF_8)
  fail_with("Package metadata is not valid UTF-8: #{path}") unless data.valid_encoding?
  header = data.split(/\r?\n\r?\n/, 2).first
  fields = Hash.new { |hash, key| hash[key] = [] }
  current_key = nil
  header.split(/\r?\n/).each do |line|
    if line.start_with?(" ", "\t")
      fail_with("Invalid package metadata continuation: #{path}") unless current_key
      fields[current_key][-1] = "#{fields[current_key][-1]}\n#{line.strip}"
      next
    end
    key, value = line.split(":", 2)
    fail_with("Invalid package metadata header: #{path}") unless value
    current_key = key
    fields[key] << value.strip
  end
  fields
end

def archive_path(path)
  path.split("\0", 2).first
end

def validate_archive_entry(entry)
  path = archive_path(entry.full_name)
  return nil if path == "././@PaxHeader" && entry.header.typeflag == "x"
  parts = path.split("/")
  fail_with("Runtime notice archive contains an unsafe path") if
    path.empty? || path.start_with?("/") || parts.include?("..")
  fail_with("Runtime notice archive contains an unexpected root") unless parts.first == "python"
  type = entry.header.typeflag
  fail_with("Runtime notice archive contains an unsupported entry type") unless
    ["0", "\0", "1", "2", "5"].include?(type)
  return path unless ["1", "2"].include?(type)

  target = entry.header.linkname
  fail_with("Runtime notice archive contains an unsafe link") if
    target.empty? || target.start_with?("/")
  base = type == "2" ? File.dirname(path) : "."
  resolved = Pathname.new(File.join(base, target)).cleanpath.to_s
  resolved_parts = resolved.split("/")
  fail_with("Runtime notice archive link escapes its root") if
    resolved == ".." || resolved.start_with?("../")
  fail_with("Runtime notice archive link has an unexpected root") unless
    resolved_parts.first == "python"
  path
end

fail_with("Usage: #{$PROGRAM_NAME} STAGED_ROOT SOURCE_MANIFEST LICENSE_POLICY NOTICE_ARCHIVE NOTICE_OUTPUT INVENTORY_OUTPUT") unless
  ARGV.length == 6

root = File.realpath(ARGV.fetch(0))
source_manifest_path = File.realpath(ARGV.fetch(1))
license_policy_path = File.realpath(ARGV.fetch(2))
notice_archive_path = File.realpath(ARGV.fetch(3))
notice_output = File.expand_path(ARGV.fetch(4))
inventory_output = File.expand_path(ARGV.fetch(5))
source = JSON.parse(File.read(source_manifest_path))
policy = JSON.parse(File.read(license_policy_path))
notice_source = source.fetch("noticeSource")

fail_with("License policy schema is unsupported") unless policy.fetch("schema") == 1
fail_with("License policy is not a candidate inventory") unless
  policy.fetch("status") == "candidate-inventory"
fail_with("Runtime notice source digest mismatch") unless
  Digest::SHA256.file(notice_archive_path).hexdigest == notice_source.fetch("sha256")

metadata_policy = notice_source.fetch("metadata")
expected_runtime_files = notice_source.fetch("licenseFiles").to_h do |item|
  [item.fetch("path"), item.fetch("sha256")]
end
expected_paths = expected_runtime_files.keys + [metadata_policy.fetch("path")]
runtime_contents = {}

Tempfile.create(["apple-companion-runtime-notices", ".tar"]) do |temporary_tar|
  temporary_tar.close
  fail_with("Unable to decompress the runtime notice archive") unless
    system("zstd", "-dc", notice_archive_path, out: temporary_tar.path)
  File.open(temporary_tar.path, "rb") do |file|
    Gem::Package::TarReader.new(file) do |archive|
      archive.each do |entry|
        path = validate_archive_entry(entry)
        next unless path
        type = entry.header.typeflag
        if path.start_with?("python/licenses/")
          fail_with("Runtime notice archive contains an unpinned license file: #{path}") unless
            expected_runtime_files.key?(path)
          fail_with("Runtime notice archive license file is not regular: #{path}") unless
            ["0", "\0"].include?(type)
        end
        next unless expected_paths.include?(path)
        fail_with("Runtime notice archive expected file is not regular: #{path}") unless
          ["0", "\0"].include?(type)
        fail_with("Runtime notice archive contains a duplicate expected file: #{path}") if
          runtime_contents.key?(path)
        runtime_contents[path] = entry.read
      end
    end
  end
end

missing_runtime_paths = expected_paths - runtime_contents.keys
fail_with("Runtime notice archive is missing expected files: #{missing_runtime_paths.join(", ")}") unless
  missing_runtime_paths.empty?

metadata_data = runtime_contents.fetch(metadata_policy.fetch("path"))
fail_with("Runtime notice metadata digest mismatch") unless
  sha256(metadata_data) == metadata_policy.fetch("sha256")
runtime_metadata = JSON.parse(metadata_data)
{
  "pythonVersion" => "python_version",
  "targetTriple" => "target_triple",
  "licensePath" => "license_path",
  "licenses" => "licenses",
}.each do |policy_key, metadata_key|
  fail_with("Runtime notice metadata mismatch for #{metadata_key}") unless
    runtime_metadata.fetch(metadata_key) == metadata_policy.fetch(policy_key)
end

expected_runtime_files.each do |path, expected_sha256|
  data = runtime_contents.fetch(path)
  fail_with("Runtime notice file digest mismatch: #{path}") unless sha256(data) == expected_sha256
  normalize_notice_text(data, path)
end

site_packages = File.join(root, "python/lib/python3.13/site-packages")
policy_packages = policy.fetch("packages").to_h do |item|
  [[item.fetch("name"), item.fetch("version")], item]
end
fail_with("License policy contains duplicate packages") unless
  policy_packages.length == policy.fetch("packages").length

package_directories = Dir.children(site_packages)
  .select { |name| name.end_with?(".dist-info") && !name.start_with?("pip-") }
  .map { |name| File.join(site_packages, name) }
  .sort

packages = package_directories.map do |directory|
  fields = parse_metadata(File.join(directory, "METADATA"))
  name = fields.fetch("Name").fetch(0)
  version = fields.fetch("Version").fetch(0)
  package_policy = policy_packages.fetch([name, version]) do
    fail_with("Staged package is missing from the license policy: #{name}==#{version}")
  end
  evidence = {
    "licenseExpression" => fields.fetch("License-Expression", [nil]).fetch(0),
    "license" => fields.fetch("License", [nil]).fetch(0),
    "licenseClassifiers" => fields.fetch("Classifier", []).select do |value|
      value.start_with?("License ::")
    end,
  }
  fail_with("Package license metadata drifted: #{name}==#{version}") unless
    evidence == package_policy.fetch("expectedEvidence")

  resolution = package_policy.fetch("resolution")
  resolved_expression = package_policy.fetch("resolvedExpression")
  case resolution
  when "license-expression"
    fail_with("Package license expression resolution mismatch: #{name}==#{version}") unless
      evidence.fetch("licenseExpression") == resolved_expression
  when "legacy-license-field"
    fail_with("Package legacy license resolution has no evidence: #{name}==#{version}") unless
      evidence.fetch("licenseExpression").nil? && evidence.fetch("license")
  when "classifier"
    fail_with("Package classifier resolution has conflicting evidence: #{name}==#{version}") unless
      evidence.fetch("licenseExpression").nil? && evidence.fetch("license").nil? &&
      !evidence.fetch("licenseClassifiers").empty?
  else
    fail_with("Package license resolution is unsupported: #{name}==#{version}")
  end

  review_status = package_policy.fetch("reviewStatus")
  fail_with("Package review status is unsupported: #{name}==#{version}") unless
    ["recorded", "requires-review"].include?(review_status)
  if review_status == "requires-review"
    fail_with("Package review reason is missing: #{name}==#{version}") if
      package_policy.fetch("reviewReason", "").empty?
  elsif package_policy.key?("reviewReason")
    fail_with("Recorded package unexpectedly has a review reason: #{name}==#{version}")
  end

  license_files = Find.find(directory).select do |path|
    next false unless File.file?(path)
    relative = path.delete_prefix(directory + File::SEPARATOR)
    basename = File.basename(path)
    relative.start_with?("licenses/") || basename.match?(/\A(?:LICENSE|COPYING|NOTICE|AUTHORS)/i)
  end.map do |path|
    fail_with("Package license evidence must not be a symlink: #{path}") if File.symlink?(path)
    data = File.binread(path)
    {
      "path" => path.delete_prefix(root + File::SEPARATOR),
      "sha256" => sha256(data),
      "text" => normalize_notice_text(data, path),
    }
  end.sort_by { |item| item.fetch("path") }
  fail_with("Package has no retained license evidence: #{name}==#{version}") if license_files.empty?

  {
    "name" => name,
    "version" => version,
    "licenseExpression" => evidence.fetch("licenseExpression"),
    "license" => evidence.fetch("license"),
    "licenseClassifiers" => evidence.fetch("licenseClassifiers"),
    "resolvedExpression" => resolved_expression,
    "resolution" => resolution,
    "reviewStatus" => review_status,
    "reviewReason" => package_policy["reviewReason"],
    "licenseFiles" => license_files,
  }
end.sort_by { |item| [item.fetch("name").downcase, item.fetch("version")] }

discovered_package_keys = packages.map { |item| [item.fetch("name"), item.fetch("version")] }
missing_policy_packages = policy_packages.keys - discovered_package_keys
fail_with("License policy contains packages absent from the staged runtime") unless
  missing_policy_packages.empty?

runtime_file_inventory = expected_runtime_files.keys.sort.map do |path|
  { "path" => path, "sha256" => expected_runtime_files.fetch(path) }
end
inventory_packages = packages.map do |item|
  item.reject { |key, _value| key == "reviewReason" && item[key].nil? }.merge(
    "licenseFiles" => item.fetch("licenseFiles").map { |file| file.reject { |key, _value| key == "text" } }
  )
end
inventory = {
  "schema" => 1,
  "noticeSource" => notice_source.reject { |key, _value| key == "licenseFiles" }.merge(
    "licenseFiles" => runtime_file_inventory
  ),
  "packages" => inventory_packages,
}

notice = +"# Apple Companion Runtime Notices\n\n"
notice << "This generated file is a deterministic engineering inventory of retained notice text. "
notice << "It is not legal advice, does not establish that every obligation is satisfied, and does not approve distribution.\n\n"
notice << "For stable Markdown rendering, source line endings are normalized to LF and trailing horizontal whitespace is removed. "
notice << "Each recorded SHA-256 identifies the original source bytes.\n\n"
notice << "The packaged runtime candidate is `#{source.fetch("source").fetch("asset")}` with SHA-256 "
notice << "`#{source.fetch("source").fetch("sha256")}`.\n\n"
notice << "## Unresolved Review Items\n\n"
packages.select { |item| item.fetch("reviewStatus") == "requires-review" }.each do |item|
  notice << "- `#{item.fetch("name")}==#{item.fetch("version")}` (`#{item.fetch("resolvedExpression")}`): "
  notice << "#{item.fetch("reviewReason")}\n"
end
notice << "\n## Runtime Notice Proxy\n\n"
notice << "The stripped runtime artifact does not contain the build project's bundled-library notice set. "
notice << "The files in this section come from the pinned `#{notice_source.fetch("asset")}` asset from the same "
notice << "`#{notice_source.fetch("release")}` release. They are a conservative same-release proxy, not proof that "
notice << "every listed component remains in the pruned candidate or that no other obligation exists.\n\n"
notice << "- Proxy relationship: `#{notice_source.fetch("relationship")}`\n"
notice << "- Proxy SHA-256: `#{notice_source.fetch("sha256")}`\n"
notice << "- Metadata SHA-256: `#{metadata_policy.fetch("sha256")}`\n\n"
runtime_file_inventory.each do |item|
  path = item.fetch("path")
  text = normalize_notice_text(runtime_contents.fetch(path), path)
  notice << "### `#{path}`\n\n"
  notice << "SHA-256: `#{item.fetch("sha256")}`\n\n"
  notice << text
  notice << "\n" unless notice.end_with?("\n")
  notice << "\n"
end

notice << "## Python Distributions\n\n"
packages.each do |item|
  notice << "### `#{item.fetch("name")}==#{item.fetch("version")}`\n\n"
  notice << "- Resolved expression: `#{item.fetch("resolvedExpression")}`\n"
  notice << "- Resolution evidence: `#{item.fetch("resolution")}`\n"
  notice << "- Review status: `#{item.fetch("reviewStatus")}`\n"
  if item.fetch("reviewStatus") == "requires-review"
    notice << "- Review reason: #{item.fetch("reviewReason")}\n"
  end
  notice << "\n"
  item.fetch("licenseFiles").each do |license_file|
    notice << "#### `#{license_file.fetch("path")}`\n\n"
    notice << "SHA-256: `#{license_file.fetch("sha256")}`\n\n"
    notice << license_file.fetch("text")
    notice << "\n" unless notice.end_with?("\n")
    notice << "\n"
  end
end

notice.sub!(/\n+\z/, "\n")
write_atomic(notice_output, notice)
write_atomic(inventory_output, JSON.pretty_generate(inventory) + "\n")
