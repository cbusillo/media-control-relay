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

swift test
scripts/check-secrets.sh
shellcheck scripts/check.sh scripts/check-secrets.sh scripts/generate-project.sh
actionlint .github/workflows/validation.yml
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
