#!/bin/sh
set -eu
repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
root="$(mktemp -d "${TMPDIR:-/tmp}/mcr-absence-test.XXXXXX")"
trap 'rm -rf "$root" || printf "Temporary test copy remains: %s\n" "$root" >&2' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
app="$root/Test.app"
ditto "${1:?Pass a built app}" "$app"
"$repo_root/scripts/check-no-apple-runtime.sh" "$app"
mkdir -p "$app/Contents/Resources"
printf '# retired helper fixture\n' >"$app/Contents/Resources/helper.py"
if "$repo_root/scripts/check-no-apple-runtime.sh" "$app" >/dev/null 2>&1; then
	printf 'Runtime absence guard accepted a planted Python helper\n' >&2
	exit 1
fi
rm "$app/Contents/Resources/helper.py"
ln -s missing "$app/Contents/Resources/AppleCompanionRuntime"
if "$repo_root/scripts/check-no-apple-runtime.sh" "$app" >/dev/null 2>&1; then
	printf 'Runtime absence guard accepted a dangling helper path\n' >&2
	exit 1
fi
printf 'Runtime absence negative checks passed.\n'
