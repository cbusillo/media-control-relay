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

swift test
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
