#!/bin/sh

set -eu
umask 022

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
source_root="$repo_root/AppleCompanionHelper"
source_manifest="$source_root/runtime-source.json"
license_policy="$source_root/license-policy.json"
committed_notices="$source_root/NOTICES.md"
notice_generator="$repo_root/scripts/generate-apple-companion-notices.rb"
scratch_root="$repo_root/scratch"
cache_root="$scratch_root/apple-companion-runtime-cache"
candidate_marker=".media-control-relay-apple-companion-runtime-candidate"
partial_asset=""
staging=""

cleanup() {
	[ -z "$partial_asset" ] || rm -f "$partial_asset"
	[ -z "$staging" ] || rm -rf "$staging"
}
trap cleanup EXIT HUP INT TERM

usage() {
	printf 'Usage: %s OUTPUT_PATH_UNDER_SCRATCH\n' "$0" >&2
	exit 64
}

[ "$#" -eq 1 ] || usage
mkdir -p "$scratch_root"
resolved_scratch="$(ruby -e 'puts File.realpath(ARGV.fetch(0))' "$scratch_root")"
cache_root="$resolved_scratch/apple-companion-runtime-cache"
output_expanded="$(ruby -e 'puts File.expand_path(ARGV.fetch(0))' "$1")"
output_parent="$(dirname "$output_expanded")"
output_name="$(basename "$output_expanded")"
[ "$output_name" != . ] && [ "$output_name" != .. ] || usage
mkdir -p "$output_parent"
resolved_output_parent="$(ruby -e 'puts File.realpath(ARGV.fetch(0))' "$output_parent")"
output="$resolved_output_parent/$output_name"
case "$output" in
"$resolved_scratch"/*) ;;
*)
	printf 'Runtime staging output must remain under %s\n' "$resolved_scratch" >&2
	exit 64
	;;
esac
if [ -e "$output" ] || [ -L "$output" ]; then
	[ -d "$output" ] && [ ! -L "$output" ] &&
		[ "$(cat "$output/$candidate_marker" 2>/dev/null || true)" = \
			"media-control-relay-apple-companion-runtime-candidate-v1" ] || {
		printf 'Refusing to replace a path that is not a staged runtime candidate\n' >&2
		exit 2
	}
fi

for command_name in cmp curl file jq lipo ruby shasum tar uv zstd; do
	command -v "$command_name" >/dev/null 2>&1 || {
		printf '%s is required to stage the Apple Companion runtime\n' "$command_name" >&2
		exit 69
	}
done

python_version="$(jq -er '.pythonVersion' "$source_manifest")"
asset_name="$(jq -er '.source.asset' "$source_manifest")"
asset_url="$(jq -er '.source.url' "$source_manifest")"
asset_sha256="$(jq -er '.source.sha256' "$source_manifest")"
expected_architecture="$(jq -er '.source.architecture' "$source_manifest")"
notice_asset_name="$(jq -er '.noticeSource.asset' "$source_manifest")"
notice_asset_url="$(jq -er '.noticeSource.url' "$source_manifest")"
notice_asset_sha256="$(jq -er '.noticeSource.sha256' "$source_manifest")"

mkdir -p "$cache_root"
downloaded_asset_path=""
download_asset() {
	asset_label="$1"
	download_name="$2"
	download_url="$3"
	download_sha256="$4"
	download_path="$cache_root/$download_name"
	if [ -f "$download_path" ]; then
		actual_download_sha256="$(shasum -a 256 "$download_path" | awk '{ print $1 }')"
		[ "$actual_download_sha256" = "$download_sha256" ] || rm -f "$download_path"
	fi
	if [ ! -f "$download_path" ]; then
		partial_asset="$download_path.part.$$"
		rm -f "$partial_asset"
		curl --fail --location --retry 3 --output "$partial_asset" "$download_url"
		partial_sha256="$(shasum -a 256 "$partial_asset" | awk '{ print $1 }')"
		[ "$partial_sha256" = "$download_sha256" ] || {
			rm -f "$partial_asset"
			printf 'Downloaded %s digest mismatch\n' "$asset_label" >&2
			exit 1
		}
		mv "$partial_asset" "$download_path"
		partial_asset=""
	fi
	actual_download_sha256="$(shasum -a 256 "$download_path" | awk '{ print $1 }')"
	[ "$actual_download_sha256" = "$download_sha256" ] || {
		printf '%s digest mismatch\n' "$asset_label" >&2
		exit 1
	}
	downloaded_asset_path="$download_path"
}

download_asset "Apple Companion runtime asset" "$asset_name" "$asset_url" "$asset_sha256"
asset_path="$downloaded_asset_path"
download_asset "Apple Companion runtime notice asset" \
	"$notice_asset_name" "$notice_asset_url" "$notice_asset_sha256"
notice_asset_path="$downloaded_asset_path"

ruby -rpathname -rrubygems/package -rzlib -e '
	Zlib::GzipReader.open(ARGV.fetch(0)) do |gzip|
	  Gem::Package::TarReader.new(gzip) do |archive|
	    archive.each do |entry|
	      path = entry.full_name.split("\0", 2).first
	      parts = path.split("/")
	      exit 1 if path.empty? || path.start_with?("/") || parts.include?("..")
	      exit 1 unless parts.first == "python"
	      type = entry.header.typeflag
	      exit 1 unless ["0", "\0", "1", "2", "5"].include?(type)
	      next unless ["1", "2"].include?(type)
	      target = entry.header.linkname
	      exit 1 if target.empty? || target.start_with?("/")
	      base = type == "2" ? File.dirname(path) : "."
	      resolved = Pathname.new(File.join(base, target)).cleanpath.to_s
	      resolved_parts = resolved.split("/")
	      exit 1 if resolved == ".." || resolved.start_with?("../")
	      exit 1 unless resolved_parts.first == "python"
	    end
	  end
	end
' "$asset_path" || {
	printf 'Apple Companion runtime archive contains an unsafe path\n' >&2
	exit 1
}

staging="$(mktemp -d "$(dirname "$output")/.apple-companion-runtime-staging.XXXXXX")"
tar -xzf "$asset_path" -C "$staging"

python_executable="$staging/python/bin/python3.13"
[ -x "$python_executable" ] || {
	printf 'Staged runtime is missing its interpreter\n' >&2
	exit 1
}
[ "$($python_executable --version 2>&1)" = "Python $python_version" ] || {
	printf 'Staged runtime has the wrong Python version\n' >&2
	exit 1
}
[ "$(lipo -archs "$python_executable")" = "$expected_architecture" ] || {
	printf 'Staged runtime has the wrong architecture\n' >&2
	exit 1
}

requirements="$staging/requirements.txt"
uv export \
	--project "$source_root" \
	--locked \
	--no-dev \
	--format requirements-txt \
	--no-emit-project \
	--no-header >"$requirements"
requirements_sha256="$(shasum -a 256 "$requirements" | awk '{ print $1 }')"
uv pip install \
	--python "$python_executable" \
	--target "$staging/python/lib/python3.13/site-packages" \
	--require-hashes \
	--no-deps \
	-r "$requirements"

ruby -rbase64 -rcsv -rdigest -e '
	root = File.realpath(ARGV.fetch(0))
	site_packages = File.join(root, "python/lib/python3.13/site-packages")
	record_paths = Dir.children(site_packages)
	  .select { |name| name.end_with?(".dist-info") }
	  .map { |name| File.join(site_packages, name, "RECORD") }
	  .select { |path| File.file?(path) }
	  .sort
	record_paths.each do |record_path|
	  next if File.basename(File.dirname(record_path)).start_with?("pip-")
	  record_relative = record_path.delete_prefix(site_packages + File::SEPARATOR)
	  CSV.read(record_path).each do |row|
	    relative, recorded_digest, recorded_size = row
	    next if relative == record_relative
	    target = File.expand_path(relative, site_packages)
	    exit 1 unless target.start_with?(root + File::SEPARATOR) && File.file?(target)
	    data = File.binread(target)
	    encoded = Base64.strict_encode64(Digest::SHA256.digest(data))
	      .tr("+/", "-_")
	      .delete("=")
	    exit 1 unless recorded_digest == "sha256=#{encoded}"
	    exit 1 unless recorded_size == data.bytesize.to_s
	  end
	end
' "$staging" || {
	printf 'Installed wheel contents do not match their RECORD metadata\n' >&2
	exit 1
}

install -m 644 "$source_root/helper.py" "$staging/helper.py"
printf 'media-control-relay-apple-companion-runtime-candidate-v1\n' \
	>"$staging/$candidate_marker"
mkdir -p "$staging/bin"
cat >"$staging/bin/apple-companion-helper" <<'EOF'
#!/bin/sh
set -eu
runtime_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
exec "$runtime_root/python/bin/python3.13" -I -B "$runtime_root/helper.py"
EOF
chmod 755 "$staging/bin/apple-companion-helper"

rm -rf \
	"$staging/python/include" \
	"$staging/python/share" \
	"$staging/python/lib/pkgconfig" \
	"$staging/python/lib/tcl8" \
	"$staging/python/lib/tcl8.6" \
	"$staging/python/lib/tk8.6" \
	"$staging/python/lib/itcl4.2.4" \
	"$staging/python/lib/thread2.8.9" \
	"$staging/python/lib/python3.13/idlelib" \
	"$staging/python/lib/python3.13/tkinter" \
	"$staging/python/lib/python3.13/turtledemo" \
	"$staging/python/lib/python3.13/test" \
	"$staging/python/lib/python3.13/ensurepip" \
	"$staging/python/lib/python3.13/config-3.13-darwin" \
	"$staging/python/lib/python3.13/site-packages/pip" \
	"$staging/python/lib/python3.13/site-packages/bin"
rm -f \
	"$staging/python/lib/libtcl8.6.dylib" \
	"$staging/python/lib/libtk8.6.dylib" \
	"$staging/python/bin/idle3" \
	"$staging/python/bin/idle3.13" \
	"$staging/python/bin/pip" \
	"$staging/python/bin/pip3" \
	"$staging/python/bin/pip3.13" \
	"$staging/python/bin/pydoc3" \
	"$staging/python/bin/pydoc3.13" \
	"$staging/python/bin/python3-config" \
	"$staging/python/bin/python3.13-config" \
	"$staging/python/lib/python3.13/lib-dynload/_ctypes_test.cpython-313-darwin.so" \
	"$staging/python/lib/python3.13/lib-dynload/_tkinter.cpython-313-darwin.so"
find "$staging/python/lib/python3.13/site-packages" \
	-maxdepth 1 -type d -name 'pip-*.dist-info' -exec rm -rf {} +
find "$staging" -type d -name __pycache__ -prune -exec rm -rf {} +
find "$staging" -type f -name '*.pyc' -delete
rm -f "$requirements"

ruby -rcsv -rjson -e '
	root = File.realpath(ARGV.fetch(0))
	site_packages = File.join(root, "python/lib/python3.13/site-packages")
	pruned_entries = []
	record_paths = Dir.children(site_packages)
	  .select { |name| name.end_with?(".dist-info") }
	  .map { |name| File.join(site_packages, name, "RECORD") }
	  .select { |path| File.file?(path) }
	  .sort
	record_paths.each do |record_path|
	  record_relative = record_path.delete_prefix(site_packages + File::SEPARATOR)
	  rows = CSV.read(record_path).map do |row|
	    relative = row.fetch(0)
	    next [relative, "", ""] if relative == record_relative
	    target = File.expand_path(relative, site_packages)
	    exit 1 unless target.start_with?(root + File::SEPARATOR)
	    if File.file?(target)
	      row
	    else
	      exit 1 unless relative.start_with?("bin/")
	      pruned_entries << { "record" => record_relative, "path" => relative }
	      nil
	    end
	  end.compact
	  rows << [record_relative, "", ""] unless rows.any? { |row| row.fetch(0) == record_relative }
	  File.open(record_path, "w") do |file|
	    rows.sort.each do |row|
	      if row.fetch(0) == record_relative
	        file.write("#{record_relative},,\n")
	      else
	        file.write(CSV.generate_line(row, row_sep: "\n"))
	      end
	    end
	  end
	end
	File.write(
	  File.join(root, ".pruned-record-entries.json"),
	  JSON.pretty_generate(pruned_entries.sort_by { |item| [item.fetch("record"), item.fetch("path")] }) + "\n"
	)
' "$staging" || {
	printf 'Pruned wheel contents do not match the approved reconciliation set\n' >&2
	exit 1
}

license_inventory="$staging/.license-inventory.json"
ruby "$notice_generator" \
	"$staging" \
	"$source_manifest" \
	"$license_policy" \
	"$notice_asset_path" \
	"$staging/NOTICES.md" \
	"$license_inventory"
cmp -s "$staging/NOTICES.md" "$committed_notices" || {
	printf 'Generated Apple Companion notices do not match the committed inventory\n' >&2
	exit 1
}

find "$staging" -type d -exec chmod 755 {} +
find "$staging" -type f -exec chmod 644 {} +
chmod 755 "$staging/bin/apple-companion-helper" "$python_executable"

ruby -rfind -e '
	root = File.realpath(ARGV.fetch(0))
	Find.find(root) do |path|
	  next unless File.symlink?(path)
	  target = File.realpath(path)
	  exit 1 unless target.start_with?(root + File::SEPARATOR)
	  exit 1 if File.readlink(path).start_with?(File::SEPARATOR)
	end
' "$staging" || {
	printf 'Staged runtime contains an unsafe symlink\n' >&2
	exit 1
}

set +e
MEDIA_CONTROL_RELAY_SOCKET='' "$staging/bin/apple-companion-helper" >/dev/null 2>&1
launcher_status="$?"
set -e
[ "$launcher_status" -eq 2 ] || {
	printf 'Staged helper launcher did not reach its expected argument check\n' >&2
	exit 1
}

ruby -rfind -rjson -rdigest -ropen3 -e '
	root = File.realpath(ARGV.fetch(0))
	source = JSON.parse(File.read(ARGV.fetch(1)))
	requirements_sha256 = ARGV.fetch(2)
	license_inventory_path = File.join(root, ".license-inventory.json")
	license_inventory = JSON.parse(File.read(license_inventory_path))
	File.delete(license_inventory_path)
	pruned_entries_path = File.join(root, ".pruned-record-entries.json")
	pruned_record_entries = JSON.parse(File.read(pruned_entries_path))
	File.delete(pruned_entries_path)
	packages = license_inventory.fetch("packages")
	mach_o_magics = %w[feedface feedfacf cefaedfe cffaedfe cafebabe bebafeca cafebabf bfbafeca]
	paths = Find.find(root).to_a.sort
	native_code = paths.map do |path|
	  next if File.symlink?(path) || !File.file?(path)
	  magic = File.binread(path, 4).unpack1("H*") rescue nil
	  next unless mach_o_magics.include?(magic)
	  architectures, lipo_status = Open3.capture2("lipo", "-archs", path)
	  raise "Unable to inspect #{path}" unless lipo_status.success?
	  {
	    "path" => path.delete_prefix(root + File::SEPARATOR),
	    "architectures" => architectures.split.sort,
	    "sha256" => Digest::SHA256.file(path).hexdigest,
	  }
	end.compact
	digest_lines = paths.map do |path|
	  relative = path.delete_prefix(root + File::SEPARATOR)
	  next if relative.empty? || relative == "manifest.json" || File.directory?(path)
	  mode = format("%03o", File.lstat(path).mode & 0o777)
	  if File.symlink?(path)
	    "link:#{relative}:#{mode}:#{File.readlink(path)}"
	  elsif File.file?(path)
	    "file:#{relative}:#{mode}:#{Digest::SHA256.file(path).hexdigest}"
	  end
	end.compact
	manifest = {
	  "schema" => 1,
	  "source" => source.fetch("source"),
	  "pythonVersion" => source.fetch("pythonVersion"),
	  "architecturePolicy" => source.fetch("architecturePolicy"),
	  "inputs" => source.fetch("inputs"),
	  "requirementsSha256" => requirements_sha256,
	  "packageCount" => packages.length,
	  "packages" => packages,
	  "runtimeNotices" => license_inventory.fetch("noticeSource"),
	  "noticeSha256" => Digest::SHA256.file(File.join(root, "NOTICES.md")).hexdigest,
	  "prunedRecordEntries" => pruned_record_entries,
	  "nativeCode" => native_code,
	  "contentSha256" => Digest::SHA256.hexdigest(digest_lines.join("\n") + "\n"),
	}
	File.write(File.join(root, "manifest.json"), JSON.pretty_generate(manifest) + "\n")
' "$staging" "$source_manifest" "$requirements_sha256"

expected_requirements_sha256="$(jq -er '.staging.requirementsSha256' "$source_manifest")"
expected_package_count="$(jq -er '.staging.packageCount' "$source_manifest")"
expected_native_code_count="$(jq -er '.staging.nativeCodeCount' "$source_manifest")"
expected_pruned_record_count="$(jq -er '.staging.prunedRecordEntryCount' "$source_manifest")"
expected_runtime_notice_count="$(jq -er '.staging.runtimeNoticeFileCount' "$source_manifest")"
expected_package_license_file_count="$(jq -er '.staging.packageLicenseFileCount' "$source_manifest")"
expected_notice_sha256="$(jq -er '.staging.noticeSha256' "$source_manifest")"
expected_content_sha256="$(jq -er '.staging.contentSha256' "$source_manifest")"
actual_requirements_sha256="$(jq -er '.requirementsSha256' "$staging/manifest.json")"
actual_package_count="$(jq -er '.packageCount' "$staging/manifest.json")"
actual_native_code_count="$(jq -er '.nativeCode | length' "$staging/manifest.json")"
actual_pruned_record_count="$(jq -er '.prunedRecordEntries | length' "$staging/manifest.json")"
actual_runtime_notice_count="$(jq -er '.runtimeNotices.licenseFiles | length' "$staging/manifest.json")"
actual_package_license_file_count="$(jq -er '[.packages[].licenseFiles[]] | length' "$staging/manifest.json")"
actual_notice_sha256="$(jq -er '.noticeSha256' "$staging/manifest.json")"
actual_content_sha256="$(jq -er '.contentSha256' "$staging/manifest.json")"
[ "$actual_requirements_sha256" = "$expected_requirements_sha256" ] &&
	[ "$actual_package_count" = "$expected_package_count" ] &&
	[ "$actual_native_code_count" = "$expected_native_code_count" ] &&
	[ "$actual_pruned_record_count" = "$expected_pruned_record_count" ] &&
	[ "$actual_runtime_notice_count" = "$expected_runtime_notice_count" ] &&
	[ "$actual_package_license_file_count" = "$expected_package_license_file_count" ] &&
	[ "$actual_notice_sha256" = "$expected_notice_sha256" ] &&
	[ "$actual_content_sha256" = "$expected_content_sha256" ] || {
	printf 'Staged runtime does not match the pinned candidate manifest\n' >&2
	printf 'runtime-notice-files %s\n' "$actual_runtime_notice_count" >&2
	printf 'package-license-files %s\n' "$actual_package_license_file_count" >&2
	printf 'notice-sha256 %s\n' "$actual_notice_sha256" >&2
	printf 'content-sha256 %s\n' "$actual_content_sha256" >&2
	exit 1
}

rm -rf "$output"
mv "$staging" "$output"
staging=""
printf 'staged %s\n' "$output"
printf 'content-sha256 %s\n' "$(jq -er '.contentSha256' "$output/manifest.json")"
