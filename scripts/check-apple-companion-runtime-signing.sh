#!/bin/sh

set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
packager="$repo_root/scripts/package-apple-companion-runtime.sh"
runtime_checker="$repo_root/scripts/check-apple-companion-runtime.sh"
runtime_contract="$repo_root/AppleCompanionHelper/runtime-contract.json"
entitlements="$repo_root/Config/MediaControlRelay.entitlements"
temporary_directory=""

cleanup() {
	[ -z "$temporary_directory" ] || rm -rf "$temporary_directory"
}
trap cleanup EXIT HUP INT TERM

usage() {
	printf 'Usage: %s RELEASE_APP CANDIDATE_PATH APP_STORE_APP\n' "$0" >&2
	exit 64
}

[ "$#" -eq 3 ] || usage
release_app="$1"
candidate="$2"
app_store_app="$3"
app_store_entitlements="$repo_root/Config/MediaControlRelayAppStore.entitlements"

for command_name in codesign ditto jq rg ruby; do
	command -v "$command_name" >/dev/null 2>&1 || {
		printf '%s is required to check Apple Companion runtime signing\n' "$command_name" >&2
		exit 69
	}
done

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/media-control-relay-signing-check.XXXXXX")"
signed_app="$temporary_directory/Media Control Relay.app"
rejected_app="$temporary_directory/App Store.app"
sandbox_refusal="$temporary_directory/sandbox-refusal"
invalid_candidate="$temporary_directory/invalid-candidate"
invalid_candidate_app="$temporary_directory/Invalid Candidate.app"
escaping_app="$temporary_directory/Escaping Resources.app"
partial_failure_app="$temporary_directory/Partial Failure.app"
ditto --norsrc --noextattr --noqtn "$release_app" "$signed_app"

"$packager" "$signed_app" "$candidate" -
codesign --force --options runtime --timestamp=none \
	--entitlements "$entitlements" --sign - "$signed_app" >/dev/null 2>&1
codesign --verify --deep --strict --all-architectures "$signed_app" \
	>/dev/null 2>&1

runtime_relative_path="$(jq -er '.bundleRelativePath' "$runtime_contract")"
runtime_root="$signed_app/$runtime_relative_path"
native_code_count="$(jq -er '.nativeCode | length' "$runtime_root/manifest.json")"
expected_native_code_count="$(jq -er '.signing.nativeCodeCount' \
	"$repo_root/AppleCompanionHelper/runtime-source.json")"
[ "$native_code_count" -eq "$expected_native_code_count" ] || {
	printf 'Signed Apple Companion native-code count is invalid\n' >&2
	exit 1
}

jq -er '.nativeCode[].path' "$runtime_root/manifest.json" |
	while IFS= read -r relative_path; do
		codesign --verify --strict --all-architectures \
			"$runtime_root/$relative_path" >/dev/null 2>&1
		signature_details="$(codesign -dv --verbose=4 \
			"$runtime_root/$relative_path" 2>&1)"
		printf '%s\n' "$signature_details" | rg -q 'flags=.*runtime' || {
			printf 'Signed Apple Companion native-code leaf lacks hardened runtime\n' >&2
			exit 1
		}
	done

app_entitlements="$(codesign -d --entitlements - "$signed_app" 2>/dev/null || true)"
if printf '%s\n' "$app_entitlements" | rg -q \
	'com\.apple\.security\.cs\.(disable-library-validation|allow-dyld-environment-variables|allow-unsigned-executable-memory|disable-executable-page-protection)'; then
	printf 'Signed application has a forbidden code-signing entitlement\n' >&2
	exit 1
fi

if "$runtime_checker" "$runtime_root" >/dev/null 2>&1; then
	printf 'Signed runtime unexpectedly passed the unsigned provenance boundary\n' >&2
	exit 1
fi
"$runtime_checker" "$candidate" >/dev/null

expect_invalid_signature() {
	app_path="$1"
	if codesign --verify --deep --strict --all-architectures "$app_path" >/dev/null 2>&1; then
		printf 'Tampered application unexpectedly retained a valid signature\n' >&2
		exit 1
	fi
}

marker_relative_path="$(jq -er '.marker.relativePath' "$runtime_contract")"
marker_tamper_app="$temporary_directory/Marker Tamper.app"
ditto "$signed_app" "$marker_tamper_app"
printf 'tamper\n' >>"$marker_tamper_app/$runtime_relative_path/$marker_relative_path"
expect_invalid_signature "$marker_tamper_app"

python_tamper_app="$temporary_directory/Python Tamper.app"
ditto "$signed_app" "$python_tamper_app"
python_resource="$(find "$python_tamper_app/$runtime_relative_path" -type f -name '*.py' \
	-print -quit)"
[ -n "$python_resource" ] || {
	printf 'Unable to locate a Python resource for signature tamper validation\n' >&2
	exit 1
}
printf '\n# tamper\n' >>"$python_resource"
expect_invalid_signature "$python_tamper_app"

native_tamper_app="$temporary_directory/Native Tamper.app"
ditto "$signed_app" "$native_tamper_app"
native_relative_path="$(jq -er '.nativeCode[0].path' \
	"$native_tamper_app/$runtime_relative_path/manifest.json")"
printf 'tamper' >>"$native_tamper_app/$runtime_relative_path/$native_relative_path"
expect_invalid_signature "$native_tamper_app"
codesign --verify --deep --strict --all-architectures "$signed_app" \
	>/dev/null 2>&1

ditto --norsrc --noextattr --noqtn "$app_store_app" "$rejected_app"
codesign --force --options runtime --timestamp=none \
	--entitlements "$app_store_entitlements" --sign - "$rejected_app" \
	>/dev/null 2>&1
if "$packager" "$rejected_app" "$candidate" - >/dev/null 2>"$sandbox_refusal"; then
	printf 'App Store application unexpectedly accepted the Apple Companion runtime\n' >&2
	exit 1
fi
rg -Fxq 'Refusing to package the runtime into a sandboxed application' \
	"$sandbox_refusal" || {
	printf 'App Store packaging did not exercise the sandbox refusal boundary\n' >&2
	exit 1
}
[ ! -e "$rejected_app/$runtime_relative_path" ] &&
	[ ! -L "$rejected_app/$runtime_relative_path" ] || {
	printf 'Rejected App Store packaging left runtime material behind\n' >&2
	exit 1
}

ditto --norsrc --noextattr --noqtn "$candidate" "$invalid_candidate"
ruby -rjson -e '
	path = File.join(ARGV.fetch(0), "manifest.json")
	manifest = JSON.parse(File.read(path))
	manifest["contentSha256"] = "0" * 64
	File.write(path, JSON.pretty_generate(manifest) + "\n")
' "$invalid_candidate"
ditto --norsrc --noextattr --noqtn "$release_app" "$invalid_candidate_app"
if "$packager" "$invalid_candidate_app" "$invalid_candidate" - >/dev/null 2>&1; then
	printf 'Invalid candidate unexpectedly reached the signing boundary\n' >&2
	exit 1
fi
[ ! -e "$invalid_candidate_app/$runtime_relative_path" ] &&
	[ ! -L "$invalid_candidate_app/$runtime_relative_path" ] || {
	printf 'Rejected candidate packaging left runtime material behind\n' >&2
	exit 1
}

ditto --norsrc --noextattr --noqtn "$release_app" "$escaping_app"
escaping_resources="$temporary_directory/outside-resources"
mv "$escaping_app/Contents/Resources" "$escaping_resources"
ln -s "$escaping_resources" "$escaping_app/Contents/Resources"
if "$packager" "$escaping_app" "$candidate" - >/dev/null 2>&1; then
	printf 'Escaping Resources directory unexpectedly accepted runtime packaging\n' >&2
	exit 1
fi
[ ! -e "$escaping_resources/AppleCompanionRuntime" ] &&
	[ ! -L "$escaping_resources/AppleCompanionRuntime" ] || {
	printf 'Rejected escaping Resources directory received runtime material\n' >&2
	exit 1
}

ditto --norsrc --noextattr --noqtn "$release_app" "$partial_failure_app"
if "$packager" "$partial_failure_app" "$candidate" \
	'Missing Apple Companion Signing Identity' >/dev/null 2>&1; then
	printf 'Missing signing identity unexpectedly packaged the runtime\n' >&2
	exit 1
fi
[ ! -e "$partial_failure_app/$runtime_relative_path" ] &&
	[ ! -L "$partial_failure_app/$runtime_relative_path" ] || {
	printf 'Failed runtime signing left partial material behind\n' >&2
	exit 1
}

printf 'Apple Companion runtime signing checks passed.\n'
