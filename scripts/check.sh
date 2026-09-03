#!/bin/sh

set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
cd "$repo_root"

command -v actionlint >/dev/null 2>&1 || {
	printf 'actionlint is required for validation\n' >&2
	exit 69
}
command -v shellcheck >/dev/null 2>&1 || {
	printf 'ShellCheck is required for validation\n' >&2
	exit 69
}
command -v rg >/dev/null 2>&1 || {
	printf 'ripgrep is required for validation\n' >&2
	exit 69
}
command -v ruby >/dev/null 2>&1 || {
	printf 'Ruby is required for JSON and YAML validation\n' >&2
	exit 69
}
command -v uv >/dev/null 2>&1 || {
	printf 'uv is required for Apple Companion helper validation\n' >&2
	exit 69
}

swift test
helper_temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/media-control-relay-uv.XXXXXX")"
helper_environment="$helper_temporary_directory/environment"
runtime_check_root="$(mktemp -d "${TMPDIR:-/tmp}/media-control-relay-runtime.XXXXXX")"
runtime_candidate="$repo_root/scratch/.validation-apple-companion-runtime.$$"
trap 'rm -rf "$helper_temporary_directory" "$runtime_check_root" "$runtime_candidate"' EXIT HUP INT TERM
(
	cd AppleCompanionHelper
	UV_PROJECT_ENVIRONMENT="$helper_environment" \
		uv run --locked python -m unittest discover -s tests
)
helper_digest_one="$(scripts/apple-companion-helper.sh digest)"
helper_digest_two="$(scripts/apple-companion-helper.sh digest)"
[ "$helper_digest_one" = "$helper_digest_two" ] || {
	printf 'Apple Companion helper digest is not deterministic\n' >&2
	exit 1
}
if helper_status="$(scripts/apple-companion-helper.sh status --root "$runtime_check_root/missing")"; then
	printf 'Missing Apple Companion helper unexpectedly reported installed\n' >&2
	exit 1
else
	status_code="$?"
	[ "$status_code" -eq 1 ] && [ "$helper_status" = not-installed ] || {
		printf 'Missing Apple Companion helper status is invalid\n' >&2
		exit 1
	}
fi
scripts/check-apple-companion-helper.sh
scripts/check-apple-companion-runtime.sh
scripts/stage-apple-companion-runtime.sh "$runtime_candidate"
scripts/check-apple-companion-runtime.sh "$runtime_candidate"
swiftc -typecheck scripts/generate-app-icon.swift
scripts/check-secrets.sh
scripts/check-action-pins.sh
scripts/check-privacy-manifest.sh
scripts/check-app-store-export.sh
scripts/check-app-icon.sh
shellcheck \
	scripts/check.sh \
	scripts/check-action-pins.sh \
	scripts/check-app-icon.sh \
	scripts/check-app-store-export.sh \
	scripts/check-privacy-manifest.sh \
	scripts/check-secrets.sh \
	scripts/check-apple-companion-helper.sh \
	scripts/check-apple-companion-runtime.sh \
	scripts/apple-companion-helper.sh \
	scripts/stage-apple-companion-runtime.sh \
	scripts/generate-project.sh
find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) \
	-print0 | xargs -0 actionlint
ruby -e 'require "json"; JSON.parse(File.read(ARGV.fetch(0)))' \
	.github/github.json
ruby -e 'require "yaml"; YAML.safe_load(File.read(ARGV.fetch(0)), aliases: false)' \
	.github/dependabot.yml
plutil -lint Config/*.plist Config/*.entitlements Config/*.xcprivacy
git diff --check
scripts/generate-project.sh
xcodebuild \
	-project MediaControlRelay.xcodeproj \
	-scheme MediaControlRelay \
	-configuration Debug \
	-destination 'platform=macOS' \
	CODE_SIGNING_ALLOWED=NO \
	test
xcodebuild \
	-project MediaControlRelay.xcodeproj \
	-scheme MediaControlRelay \
	-configuration Release \
	-destination 'platform=macOS' \
	CODE_SIGNING_ALLOWED=NO \
	build
xcodebuild \
	-project MediaControlRelay.xcodeproj \
	-scheme MediaControlRelay \
	-configuration AppStore \
	-destination 'platform=macOS' \
	CODE_SIGNING_ALLOWED=NO \
	build
app_store_build_settings="$(xcodebuild \
	-project MediaControlRelay.xcodeproj \
	-scheme MediaControlRelay \
	-configuration AppStore \
	-destination 'platform=macOS' \
	-showBuildSettings)"
app_store_build_dir="$(printf '%s\n' "$app_store_build_settings" | awk -F' = ' '
		/Build settings for action build and target MediaControlRelay:/ { target = 1; next }
		target && /TARGET_BUILD_DIR =/ { print $2; exit }
	')"
app_store_product_name="$(printf '%s\n' "$app_store_build_settings" | awk -F' = ' '
		/Build settings for action build and target MediaControlRelay:/ { target = 1; next }
		target && /FULL_PRODUCT_NAME =/ { print $2; exit }
	')"
[ -n "$app_store_build_dir" ] && [ -n "$app_store_product_name" ] || {
	printf 'Unable to resolve the AppStore application build path\n' >&2
	exit 1
}
scripts/check-app-icon.sh "$app_store_build_dir/$app_store_product_name"
app_store_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
	"$app_store_build_dir/$app_store_product_name/Contents/Info.plist")"
if nm -gU \
	"$app_store_build_dir/$app_store_product_name/Contents/MacOS/$app_store_executable" |
	rg -q 'AppleCompanion'; then
	printf 'App Store executable unexpectedly links Apple Companion support\n' >&2
	exit 1
fi
if nm -u \
	"$app_store_build_dir/$app_store_product_name/Contents/MacOS/$app_store_executable" |
	rg -q 'AppleCompanion'; then
	printf 'App Store executable unexpectedly references Apple Companion support\n' >&2
	exit 1
fi
if strings \
	"$app_store_build_dir/$app_store_product_name/Contents/MacOS/$app_store_executable" |
	rg -q 'AppleCompanion'; then
	printf 'App Store executable unexpectedly contains Apple Companion metadata\n' >&2
	exit 1
fi
if find "$app_store_build_dir/$app_store_product_name" \
	\( -name '*.py' -o -name '*.pyc' -o -name 'pyatv*' \
	-o -name 'AppleCompanionHelper*' -o -name 'apple-companion-helper*' \
	-o -name '*.pyi' -o -name '*.pth' -o -name '*.whl' \
	-o -name '*.dist-info' -o -name 'pyvenv.cfg' -o -name 'site-packages' \
	-o -name 'libpython*' \) -print -quit | rg -q .; then
	printf 'App Store build unexpectedly contains Apple Companion helper material\n' >&2
	exit 1
fi
release_build_settings="$(xcodebuild \
	-project MediaControlRelay.xcodeproj \
	-scheme MediaControlRelay \
	-configuration Release \
	-destination 'platform=macOS' \
	-showBuildSettings)"
release_build_dir="$(printf '%s\n' "$release_build_settings" | awk -F' = ' '
		/Build settings for action build and target MediaControlRelay:/ { target = 1; next }
		target && /TARGET_BUILD_DIR =/ { print $2; exit }
	')"
release_product_name="$(printf '%s\n' "$release_build_settings" | awk -F' = ' '
		/Build settings for action build and target MediaControlRelay:/ { target = 1; next }
		target && /FULL_PRODUCT_NAME =/ { print $2; exit }
	')"
[ -n "$release_build_dir" ] && [ -n "$release_product_name" ] || {
	printf 'Unable to resolve the Release application build path\n' >&2
	exit 1
}
release_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
	"$release_build_dir/$release_product_name/Contents/Info.plist")"
if ! nm -gU \
	"$release_build_dir/$release_product_name/Contents/MacOS/$release_executable" |
	rg -q 'AppleCompanion'; then
	printf 'Release executable does not contain the live Apple Companion adapter\n' >&2
	exit 1
fi
