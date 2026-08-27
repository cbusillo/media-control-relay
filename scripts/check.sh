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
scripts/check-secrets.sh
scripts/check-action-pins.sh
shellcheck \
	scripts/check.sh \
	scripts/check-action-pins.sh \
	scripts/check-secrets.sh \
	scripts/generate-project.sh
find .github/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) \
	-print0 | xargs -0 actionlint
ruby -e 'require "json"; JSON.parse(File.read(ARGV.fetch(0)))' \
	.github/github.json
ruby -e 'require "yaml"; YAML.safe_load(File.read(ARGV.fetch(0)), aliases: false)' \
	.github/dependabot.yml
plutil -lint Config/*.plist Config/*.entitlements
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
