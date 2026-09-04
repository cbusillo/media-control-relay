#!/bin/sh

set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
source_manifest="$repo_root/AppleCompanionHelper/runtime-source.json"
runtime_contract="$repo_root/AppleCompanionHelper/runtime-contract.json"
license_policy="$repo_root/AppleCompanionHelper/license-policy.json"
committed_notices="$repo_root/AppleCompanionHelper/NOTICES.md"
notice_generator="$repo_root/scripts/generate-apple-companion-notices.rb"
runtime_path="${1:-}"

for command_name in ruby shasum; do
	command -v "$command_name" >/dev/null 2>&1 || {
		printf '%s is required to check Apple Companion runtime provenance\n' "$command_name" >&2
		exit 69
	}
done
ruby -c "$notice_generator" >/dev/null

ruby -rjson -rdigest -e '
	repo_root = File.realpath(ARGV.fetch(0))
	manifest_path = ARGV.fetch(1)
	manifest = JSON.parse(File.read(manifest_path))
	expected_source = {
	  "project" => "astral-sh/python-build-standalone",
	  "release" => "20250818",
	  "buildProjectLicense" => "MPL-2.0",
	  "artifactLicense" => "composite",
	  "artifactIncludesBundledLibraryNotices" => false,
	  "asset" => "cpython-3.13.7+20250818-aarch64-apple-darwin-install_only_stripped.tar.gz",
	  "url" => "https://github.com/astral-sh/python-build-standalone/releases/download/20250818/cpython-3.13.7%2B20250818-aarch64-apple-darwin-install_only_stripped.tar.gz",
	  "sha256" => "024a3a1c95f171e97a4eaa6d2d289baf6802b72e4767023e3d9e4fa246be11bb",
	  "architecture" => "arm64",
	}
	exit 1 unless manifest.fetch("schema") == 1
	exit 1 unless manifest.fetch("status") == "candidate"
	exit 1 unless manifest.fetch("lastVerified") == "2026-09-04"
	exit 1 unless manifest.fetch("pythonVersion") == "3.13.7"
	exit 1 unless manifest.fetch("source") == expected_source
	contract = JSON.parse(
	  File.read(File.join(repo_root, "AppleCompanionHelper/runtime-contract.json"))
	)
	exit 1 unless contract == {
	  "schema" => 1,
	  "bundleRelativePath" => "Contents/Resources/AppleCompanionRuntime",
	  "marker" => {
	    "relativePath" => ".media-control-relay-apple-companion-runtime-candidate",
	    "contents" => "media-control-relay-apple-companion-runtime-candidate-v1\n",
	  },
	  "manifestRelativePath" => "manifest.json",
	  "launcherRelativePath" => "bin/apple-companion-helper",
	  "interpreterRelativePath" => "python/bin/python3.13",
	  "pythonVersion" => "3.13.7",
	  "helperRuntimeArchitecture" => "arm64",
	  "intelBehavior" => "unsupported",
	  "contentSha256" => "10e741b0867c692e3ecf019d43f2c4bf0055246d0da66409a94cae9fcc219324",
	}
	notice_source = manifest.fetch("noticeSource")
	exit 1 unless notice_source.fetch("project") == "astral-sh/python-build-standalone"
	exit 1 unless notice_source.fetch("release") == "20250818"
	exit 1 unless notice_source.fetch("relationship") == "same-release-full-variant-proxy"
	exit 1 unless notice_source.fetch("reviewStatus") == "recorded"
	exit 1 unless notice_source.fetch("relationshipEvidence") == {
	  "fullInstallFileCount" => 3456,
	  "strippedInstallFileCount" => 1828,
	  "strippedPathsMissingFromFullInstall" => 0,
	  "byteIdenticalFileCount" => 1812,
	  "binaryTransformFileCount" => 16,
	}
	exit 1 unless notice_source.fetch("licenseFiles").length == 19
	exit 1 unless Digest::SHA256.hexdigest(JSON.generate(notice_source)) ==
	  "dc1e9b6886762cbb6bd0c93a1a5d322575e963c52fddacca3f20ff5516646f42"
	policy = manifest.fetch("architecturePolicy")
	exit 1 unless policy.fetch("application") == "universal2"
	exit 1 unless policy.fetch("helperRuntime") == "arm64"
	exit 1 unless policy.fetch("intelBehavior") == "unsupported"
	exit 1 unless policy.fetch("blockers") == [
	  {
	    "package" => "cryptography",
	    "version" => "50.0.1",
	    "reason" => "The exact PyPI release publishes macOS wheels for arm64 only.",
	  },
	]
	staging = manifest.fetch("staging")
	exit 1 unless staging == {
	  "requirementsSha256" => "a810c21cc554c114b0b6b98c4f4d08501ca301993f019b1712c84a548adbca27",
	  "packageCount" => 31,
	  "nativeCodeCount" => 17,
	  "prunedRecordEntryCount" => 28,
	  "runtimeNoticeFileCount" => 19,
	  "packageLicenseFileCount" => 38,
	  "noticeSha256" => "9e875e9e4aeeb8170c8bf8d2d8e109658a9bc5f5918e0922f1401aca09ec237f",
	  "contentSha256" => "10e741b0867c692e3ecf019d43f2c4bf0055246d0da66409a94cae9fcc219324",
	}
	exit 1 unless manifest.fetch("signing") == {
	  "strategy" => "manifest-native-code-inside-out",
	  "nativeCodeCount" => 17,
	  "hardenedRuntime" => true,
	  "shippedIntegrityBoundary" => "outer-application-code-signature",
	  "forbiddenEntitlements" => [
	    "com.apple.security.cs.disable-library-validation",
	    "com.apple.security.cs.allow-dyld-environment-variables",
	    "com.apple.security.cs.allow-unsigned-executable-memory",
	    "com.apple.security.cs.disable-executable-page-protection",
	  ],
	}
	distribution = manifest.fetch("distribution")
	exit 1 unless distribution.fetch("approved") == false
	exit 1 unless distribution.fetch("blockedBy") == [
	  "Pass clean supported-Mac qualification, including launch without developer-installed Python tooling and offline Gatekeeper behavior.",
	]
	expected_inputs = {
	  "AppleCompanionHelper/.python-version" => "3ce16e94590543a327d3e5ae412e663206e0ed1b46628ed3dd5ad29caa1ff5ac",
	  "AppleCompanionHelper/helper.py" => "fa456b34df18a5e61553c21be9b348dc45c4241824a2f57d95dd18be5d5f8721",
	  "AppleCompanionHelper/license-policy.json" => "de6fe97e046c25cb15c86f53dcc876f0105a485eb28fbdb6d0a1ddf246a40a5f",
	  "AppleCompanionHelper/NOTICES.md" => "9e875e9e4aeeb8170c8bf8d2d8e109658a9bc5f5918e0922f1401aca09ec237f",
	  "AppleCompanionHelper/pyproject.toml" => "2996be95515a1151cde0c811e24562f5da7cdbd4575fc560cfe85fa6a567410f",
	  "AppleCompanionHelper/runtime-contract.json" => "35112cb3a48c5a7f78b12f92227c0e04189409e5b77298a6b598b2a1e4fa2194",
	  "AppleCompanionHelper/uv.lock" => "80725a973bfbb4d117f095da671583b554eb18f3d45d1424f1399748f1d6bd01",
	}
	inputs = manifest.fetch("inputs").to_h do |input|
	  [input.fetch("path"), input.fetch("sha256")]
	end
	exit 1 unless inputs == expected_inputs
	expected_inputs.each do |relative, sha256|
	  path = File.expand_path(relative, repo_root)
	  exit 1 unless path.start_with?(repo_root + File::SEPARATOR)
	  exit 1 unless File.file?(path)
	  exit 1 unless Digest::SHA256.file(path).hexdigest == sha256
	end
' "$repo_root" "$source_manifest" || {
	printf 'Apple Companion runtime source manifest is invalid or stale\n' >&2
	exit 1
}

if [ -n "$runtime_path" ]; then
	command -v lipo >/dev/null 2>&1 || {
		printf 'lipo is required to check a staged Apple Companion runtime\n' >&2
		exit 69
	}
	launcher_relative="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV.fetch(0))).fetch("launcherRelativePath")' "$runtime_contract")"
	ruby -rbase64 -rcsv -rfind -rjson -rdigest -ropen3 -e '
	  root = File.realpath(ARGV.fetch(0))
	  source = JSON.parse(File.read(ARGV.fetch(1)))
	  policy = JSON.parse(File.read(ARGV.fetch(2)))
	  committed_notices = File.binread(ARGV.fetch(3))
	  contract = JSON.parse(File.read(ARGV.fetch(4)))
	  marker = File.join(root, contract.fetch("marker").fetch("relativePath"))
	  manifest_path = File.join(root, contract.fetch("manifestRelativePath"))
	  launcher_path = File.join(root, contract.fetch("launcherRelativePath"))
	  interpreter_path = File.join(root, contract.fetch("interpreterRelativePath"))
	  manifest = JSON.parse(File.read(manifest_path))
	  exit 1 unless File.read(marker) == contract.fetch("marker").fetch("contents")
	  [launcher_path, interpreter_path].each do |path|
	    info = File.lstat(path)
	    exit 1 unless info.file? && !info.symlink? && (info.mode & 0o111) != 0
	    exit 1 unless (info.mode & 0o022) == 0
	    exit 1 unless File.realpath(path).start_with?(root + File::SEPARATOR)
	  end
	  interpreter_architectures, interpreter_status = Open3.capture2("lipo", "-archs", interpreter_path)
	  exit 1 unless interpreter_status.success?
	  exit 1 unless interpreter_architectures.split == [contract.fetch("helperRuntimeArchitecture")]
	  exit 1 unless manifest.fetch("schema") == 1
	  exit 1 unless manifest.fetch("source") == source.fetch("source")
	  exit 1 unless manifest.fetch("pythonVersion") == source.fetch("pythonVersion")
	  exit 1 unless manifest.fetch("pythonVersion") == contract.fetch("pythonVersion")
	  exit 1 unless manifest.fetch("architecturePolicy") == source.fetch("architecturePolicy")
	  exit 1 unless manifest.fetch("architecturePolicy").fetch("helperRuntime") ==
	    contract.fetch("helperRuntimeArchitecture")
	  exit 1 unless manifest.fetch("architecturePolicy").fetch("intelBehavior") ==
	    contract.fetch("intelBehavior")
	  exit 1 unless manifest.fetch("contentSha256") == contract.fetch("contentSha256")
	  exit 1 unless manifest.fetch("inputs") == source.fetch("inputs")
	  expected_staging = source.fetch("staging")
	  exit 1 unless manifest.fetch("requirementsSha256") == expected_staging.fetch("requirementsSha256")
	  exit 1 unless manifest.fetch("runtimeNotices") == source.fetch("noticeSource")
	  notice_path = File.join(root, "NOTICES.md")
	  exit 1 unless File.file?(notice_path) && !File.symlink?(notice_path)
	  exit 1 unless File.binread(notice_path) == committed_notices
	  exit 1 unless Digest::SHA256.file(notice_path).hexdigest == manifest.fetch("noticeSha256")
	  exit 1 unless manifest.fetch("noticeSha256") == expected_staging.fetch("noticeSha256")
	  exit 1 unless manifest.fetch("runtimeNotices").fetch("licenseFiles").length ==
	    expected_staging.fetch("runtimeNoticeFileCount")
	  exit 1 unless manifest.fetch("packageCount") == expected_staging.fetch("packageCount")
	  packages = manifest.fetch("packages")
	  exit 1 unless packages.length == expected_staging.fetch("packageCount")
	  exit 1 unless packages.map { |item| item.fetch("name").downcase }.uniq.length == packages.length
	  policy_packages = policy.fetch("packages").to_h do |item|
	    [[item.fetch("name"), item.fetch("version")], item]
	  end
	  exit 1 unless policy.fetch("schema") == 1
	  exit 1 unless policy.fetch("status") == "candidate-inventory"
	  exit 1 unless policy_packages.length == policy.fetch("packages").length
	  package_versions = packages.map do |item|
	    [item.fetch("name"), item.fetch("version")]
	  end
	  exit 1 unless package_versions.include?(["pyatv", "0.18.0"])
	  exit 1 unless package_versions.sort == policy_packages.keys.sort
	  package_license_file_count = 0
	  packages.each do |item|
	    package_policy = policy_packages.fetch([item.fetch("name"), item.fetch("version")])
	    expected_item = {
	      "name" => package_policy.fetch("name"),
	      "version" => package_policy.fetch("version"),
	      "licenseExpression" => package_policy.fetch("expectedEvidence").fetch("licenseExpression"),
	      "license" => package_policy.fetch("expectedEvidence").fetch("license"),
	      "licenseClassifiers" => package_policy.fetch("expectedEvidence").fetch("licenseClassifiers"),
	      "resolvedExpression" => package_policy.fetch("resolvedExpression"),
	      "resolution" => package_policy.fetch("resolution"),
	      "reviewStatus" => package_policy.fetch("reviewStatus"),
	      "reviewedClassifierConflicts" => package_policy.fetch("reviewedClassifierConflicts", []),
	      "prunedFiles" => package_policy.fetch("prunedFiles", []),
	    }
	    expected_item["reviewReason"] = package_policy.fetch("reviewReason") if
	      package_policy.key?("reviewReason")
	    expected_item["reviewNote"] = package_policy.fetch("reviewNote") if
	      package_policy.key?("reviewNote")
	    expected_item["resolutionFile"] = package_policy.fetch("resolutionFile") if
	      package_policy.key?("resolutionFile")
	    exit 1 unless item.reject { |key, _value| key == "licenseFiles" } == expected_item
	    license_files = item.fetch("licenseFiles")
	    exit 1 if license_files.empty?
	    package_license_file_count += license_files.length
	    license_files.each do |license_file|
	      relative = license_file.fetch("path")
	      path = File.expand_path(relative, root)
	      exit 1 unless path.start_with?(root + File::SEPARATOR) && File.file?(path) && !File.symlink?(path)
	      exit 1 unless Digest::SHA256.file(path).hexdigest == license_file.fetch("sha256")
	    end
	  end
	  exit 1 unless package_license_file_count == expected_staging.fetch("packageLicenseFileCount")
	  review_items = packages.select { |item| item.fetch("reviewStatus") == "requires-review" }
	  exit 1 unless review_items.empty?
	  exit 1 unless source.fetch("distribution").fetch("approved") == false
	  approved_pruned_files = policy_packages.values.flat_map do |item|
	    item.fetch("prunedFiles", [])
	  end.sort
	  pruned_record_entries = manifest.fetch("prunedRecordEntries")
	  exit 1 unless pruned_record_entries.length == expected_staging.fetch("prunedRecordEntryCount")
	  exit 1 unless pruned_record_entries.uniq.length == pruned_record_entries.length
	  exit 1 unless pruned_record_entries.all? do |item|
	    path = item.fetch("path")
	    item.fetch("record").end_with?(".dist-info/RECORD") &&
	      (path.start_with?("bin/") || approved_pruned_files.include?(path))
	  end
	  observed_policy_prunes = pruned_record_entries.map { |item| item.fetch("path") }
	    .select { |path| approved_pruned_files.include?(path) }
	    .sort
	  exit 1 unless observed_policy_prunes == approved_pruned_files
	  site_packages = File.join(root, "python/lib/python3.13/site-packages")
	  record_paths = Dir.children(site_packages)
	    .select { |name| name.end_with?(".dist-info") }
	    .map { |name| File.join(site_packages, name, "RECORD") }
	    .select { |path| File.file?(path) }
	    .sort
	  record_paths.each do |record_path|
	    record_relative = record_path.delete_prefix(site_packages + File::SEPARATOR)
	    CSV.read(record_path).each do |row|
	      relative, recorded_digest, recorded_size = row
	      if relative == record_relative
	        exit 1 unless recorded_digest.to_s.empty? && recorded_size.to_s.empty?
	        next
	      end
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
	  native_code = manifest.fetch("nativeCode")
	  exit 1 unless native_code.length == expected_staging.fetch("nativeCodeCount")
	  exit 1 unless native_code.all? do |item|
	    architectures = item.fetch("architectures")
	    architectures.include?("arm64") &&
	      (architectures - ["arm64", "x86_64"]).empty?
	  end
	  mach_o_magics = %w[feedface feedfacf cefaedfe cffaedfe cafebabe bebafeca cafebabf bfbafeca]
	  paths = Find.find(root).to_a.sort
	  actual_native_code = paths.map do |path|
	    next if File.symlink?(path) || !File.file?(path)
	    magic = File.binread(path, 4).unpack1("H*") rescue nil
	    next unless mach_o_magics.include?(magic)
	    architectures, status = Open3.capture2("lipo", "-archs", path)
	    exit 1 unless status.success?
	    {
	      "path" => path.delete_prefix(root + File::SEPARATOR),
	      "architectures" => architectures.split.sort,
	      "sha256" => Digest::SHA256.file(path).hexdigest,
	    }
	  end.compact
	  exit 1 unless actual_native_code == native_code
	  digest_lines = paths.map do |path|
	    relative = path.delete_prefix(root + File::SEPARATOR)
	    next if relative.empty? || relative == "manifest.json" || File.directory?(path)
	    mode = format("%03o", File.lstat(path).mode & 0o777)
	    if File.symlink?(path)
	      target = File.realpath(path)
	      exit 1 unless target.start_with?(root + File::SEPARATOR)
	      exit 1 if File.readlink(path).start_with?(File::SEPARATOR)
	      "link:#{relative}:#{mode}:#{File.readlink(path)}"
	    elsif File.file?(path)
	      "file:#{relative}:#{mode}:#{Digest::SHA256.file(path).hexdigest}"
	    end
	  end.compact
	  actual = Digest::SHA256.hexdigest(digest_lines.join("\n") + "\n")
	  exit 1 unless actual == manifest.fetch("contentSha256")
	  exit 1 unless actual == expected_staging.fetch("contentSha256")
	' "$runtime_path" "$source_manifest" "$license_policy" "$committed_notices" "$runtime_contract" || {
		printf 'Staged Apple Companion runtime is invalid or stale\n' >&2
		exit 1
	}
	for forbidden_path in \
		python/include \
		python/share \
		python/lib/python3.13/idlelib \
		python/lib/python3.13/tkinter \
		python/lib/python3.13/test \
		python/lib/python3.13/ensurepip \
		python/lib/python3.13/config-3.13-darwin \
		python/lib/python3.13/lib-dynload/_ctypes_test.cpython-313-darwin.so; do
		[ ! -e "$runtime_path/$forbidden_path" ] || {
			printf 'Staged runtime contains forbidden path %s\n' "$forbidden_path" >&2
			exit 1
		}
	done
	[ ! -e "$runtime_path/python/lib/python3.13/site-packages/bin" ] || {
		printf 'Staged runtime contains generated console entry points\n' >&2
		exit 1
	}
	if find "$runtime_path/python/lib/python3.13/site-packages/zeroconf" \
		-type f -name '*.so' -print -quit | grep -q .; then
		printf 'Staged runtime contains forbidden zeroconf native extensions\n' >&2
		exit 1
	fi
	"$runtime_path/python/bin/python3.13" -I -B -c '
import zeroconf._dns
import zeroconf._services.browser

assert zeroconf._dns.__file__.endswith(".py")
assert zeroconf._services.browser.__file__.endswith(".py")
	' || {
		printf 'Staged runtime does not use pure-Python zeroconf\n' >&2
		exit 1
	}
	if find "$runtime_path" \( -type d -name __pycache__ -o -type f -name '*.pyc' \) \
		-print -quit | grep -q .; then
		printf 'Staged runtime contains generated bytecode\n' >&2
		exit 1
	fi
	set +e
	MEDIA_CONTROL_RELAY_SOCKET='' "$runtime_path/$launcher_relative" >/dev/null 2>&1
	launcher_status="$?"
	set -e
	[ "$launcher_status" -eq 2 ] || {
		printf 'Staged helper launcher did not reach its expected argument check\n' >&2
		exit 1
	}
fi

printf 'Apple Companion runtime provenance checks passed.\n'
