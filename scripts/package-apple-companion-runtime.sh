#!/bin/sh

set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
runtime_contract="$repo_root/AppleCompanionHelper/runtime-contract.json"
runtime_source="$repo_root/AppleCompanionHelper/runtime-source.json"
runtime_checker="$repo_root/scripts/check-apple-companion-runtime.sh"
temporary_directory=""

cleanup() {
	[ -z "$temporary_directory" ] || rm -rf "$temporary_directory"
}
trap cleanup EXIT HUP INT TERM

usage() {
	printf 'Usage: %s APP_PATH CANDIDATE_PATH SIGNING_IDENTITY\n' "$0" >&2
	exit 64
}

[ "$#" -eq 3 ] || usage
app_input="$1"
candidate_input="$2"
signing_identity="$3"

for command_name in codesign ditto jq lipo nm rg ruby; do
	command -v "$command_name" >/dev/null 2>&1 || {
		printf '%s is required to package the Apple Companion runtime\n' "$command_name" >&2
		exit 69
	}
done

[ -d "$app_input" ] && [ ! -L "$app_input" ] || {
	printf 'Developer ID application must be a regular bundle directory\n' >&2
	exit 2
}
[ -d "$candidate_input" ] && [ ! -L "$candidate_input" ] || {
	printf 'Apple Companion runtime candidate must be a regular directory\n' >&2
	exit 2
}
[ -n "$signing_identity" ] || usage

app="$(ruby -e 'puts File.realpath(ARGV.fetch(0))' "$app_input")"
candidate="$(ruby -e 'puts File.realpath(ARGV.fetch(0))' "$candidate_input")"
runtime_relative_path="$(jq -er '.bundleRelativePath' "$runtime_contract")"
case "$runtime_relative_path" in
Contents/Resources/*) ;;
*)
	printf 'Apple Companion runtime bundle path is outside Contents/Resources\n' >&2
	exit 1
	;;
esac
runtime_destination="$app/$runtime_relative_path"
contents_directory="$app/Contents"
resources_directory="$contents_directory/Resources"

[ -d "$contents_directory" ] && [ ! -L "$contents_directory" ] || {
	printf 'Application Contents directory is missing or unsafe\n' >&2
	exit 2
}
if [ -e "$resources_directory" ] || [ -L "$resources_directory" ]; then
	[ -d "$resources_directory" ] && [ ! -L "$resources_directory" ] || {
		printf 'Application Resources directory is unsafe\n' >&2
		exit 2
	}
fi

app_executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
	"$app/Contents/Info.plist")"
app_executable="$app/Contents/MacOS/$app_executable_name"
[ -f "$app_executable" ] && [ ! -L "$app_executable" ] || {
	printf 'Developer ID application executable is missing\n' >&2
	exit 2
}
if ! nm -gU "$app_executable" | rg -q 'AppleCompanion'; then
	printf 'Application does not contain the live Apple Companion adapter\n' >&2
	exit 2
fi
if app_entitlements="$(codesign -d --entitlements - "$app" 2>/dev/null || true)" &&
	printf '%s\n' "$app_entitlements" | rg -q 'com\.apple\.security\.app-sandbox'; then
	printf 'Refusing to package the runtime into a sandboxed application\n' >&2
	exit 2
fi
[ ! -e "$runtime_destination" ] && [ ! -L "$runtime_destination" ] || {
	printf 'Application already contains an Apple Companion runtime\n' >&2
	exit 2
}

"$runtime_checker" "$candidate"
mkdir -p "$resources_directory"
chmod 755 "$contents_directory" "$resources_directory"
resolved_resources="$(ruby -e 'puts File.realpath(ARGV.fetch(0))' "$resources_directory")"
[ "$resolved_resources" = "$resources_directory" ] || {
	printf 'Application Resources directory escapes the application bundle\n' >&2
	exit 2
}
ditto --norsrc --noextattr --noqtn "$candidate" "$runtime_destination"
"$runtime_checker" "$runtime_destination"

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/media-control-relay-signing.XXXXXX")"
manifest_paths="$temporary_directory/manifest-paths"
actual_paths="$temporary_directory/actual-paths"
signing_paths="$temporary_directory/signing-paths"

ruby -rjson -e '
	manifest = JSON.parse(File.read(ARGV.fetch(0)))
	expected_count = Integer(JSON.parse(File.read(ARGV.fetch(1))).fetch("staging").fetch("nativeCodeCount"))
	interpreter = JSON.parse(File.read(ARGV.fetch(2))).fetch("interpreterRelativePath")
	paths = manifest.fetch("nativeCode").map { |item| item.fetch("path") }
	exit 1 unless paths.length == expected_count && paths.uniq.length == paths.length
	exit 1 unless paths.all? do |path|
	  !path.empty? && !path.start_with?("/") && !path.split("/").include?("..") &&
	    !path.include?("\n") && !path.include?("\0")
	end
	exit 1 unless paths.include?(interpreter)
	File.write(ARGV.fetch(3), paths.sort.join("\n") + "\n")
	ordered = paths.reject { |path| path == interpreter }
	  .sort_by { |path| [-path.count("/"), -path.length, path] }
	ordered << interpreter
	File.write(ARGV.fetch(4), ordered.join("\n") + "\n")
' "$runtime_destination/manifest.json" "$runtime_source" "$runtime_contract" \
	"$manifest_paths" "$signing_paths" || {
	printf 'Apple Companion native-code signing inventory is invalid\n' >&2
	exit 1
}

ruby -rfind -e '
	root = File.realpath(ARGV.fetch(0))
	magics = %w[feedface feedfacf cefaedfe cffaedfe cafebabe bebafeca cafebabf bfbafeca]
	paths = Find.find(root).each_with_object([]) do |path, found|
	  next if File.symlink?(path) || !File.file?(path)
	  magic = File.binread(path, 4).unpack1("H*") rescue nil
	  found << path.delete_prefix(root + File::SEPARATOR) if magics.include?(magic)
	end
	File.write(ARGV.fetch(1), paths.sort.join("\n") + "\n")
' "$runtime_destination" "$actual_paths"
cmp -s "$manifest_paths" "$actual_paths" || {
	printf 'Apple Companion native-code inventory does not match the candidate manifest\n' >&2
	exit 1
}

sign_leaf() {
	leaf="$1"
	if [ "$signing_identity" = - ]; then
		codesign --force --options runtime --timestamp=none \
			--sign "$signing_identity" "$leaf" >/dev/null 2>&1
	else
		codesign --force --options runtime --timestamp \
			--sign "$signing_identity" "$leaf" >/dev/null 2>&1
	fi
}

signed_count=0
while IFS= read -r relative_path; do
	[ -n "$relative_path" ] || continue
	leaf="$runtime_destination/$relative_path"
	[ -f "$leaf" ] && [ ! -L "$leaf" ] || {
		printf 'Apple Companion native-code leaf is missing or unsafe\n' >&2
		exit 1
	}
	if ! sign_leaf "$leaf"; then
		printf 'Unable to sign an Apple Companion native-code leaf\n' >&2
		exit 1
	fi
	if ! codesign --verify --strict --all-architectures "$leaf" \
		>/dev/null 2>&1; then
		printf 'Apple Companion native-code leaf signature is invalid\n' >&2
		exit 1
	fi
	signature_details="$(codesign -dv --verbose=4 "$leaf" 2>&1)"
	printf '%s\n' "$signature_details" | rg -q 'flags=.*runtime' || {
		printf 'Apple Companion native-code leaf lacks hardened runtime\n' >&2
		exit 1
	}
	leaf_entitlements="$(codesign -d --entitlements - "$leaf" 2>/dev/null || true)"
	if printf '%s\n' "$leaf_entitlements" | rg -q \
		'com\.apple\.security\.cs\.(disable-library-validation|allow-dyld-environment-variables|allow-unsigned-executable-memory|disable-executable-page-protection)'; then
		printf 'Apple Companion native-code leaf has a forbidden entitlement\n' >&2
		exit 1
	fi
	signed_count=$((signed_count + 1))
done <"$signing_paths"

expected_count="$(jq -er '.staging.nativeCodeCount' "$runtime_source")"
[ "$signed_count" -eq "$expected_count" ] || {
	printf 'Apple Companion native-code signing count is invalid\n' >&2
	exit 1
}

printf 'packaged Apple Companion runtime\n'
printf 'signed-native-code %s\n' "$signed_count"
