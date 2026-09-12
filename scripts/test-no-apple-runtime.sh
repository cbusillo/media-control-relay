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
mkdir "$root/tools"
printf '#!/bin/sh\nexit 2\n' >"$root/tools/rg"
chmod +x "$root/tools/rg"
status=0
PATH="$root/tools:$PATH" "$repo_root/scripts/check-no-apple-runtime.sh" "$app" >"$root/tool-error" 2>&1 || status=$?
[ "$status" -eq 2 ] && grep -q 'Runtime symbol inspection failed' "$root/tool-error" || {
	printf 'Runtime absence guard did not fail closed on a search-tool error\n' >&2
	exit 1
}
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
rm "$app/Contents/Resources/AppleCompanionRuntime"
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
# Compile a valid Mach-O fixture to exercise symbol detection independently of
# filename detection and malformed-binary errors.
printf 'int AppleCompanionFixture = 1; int main(void) { return AppleCompanionFixture; }\n' |
	clang -arch arm64 -x c -o "$app/Contents/MacOS/$executable" -
nm -gU "$app/Contents/MacOS/$executable" >/dev/null
if "$repo_root/scripts/check-no-apple-runtime.sh" "$app" >"$root/result" 2>&1; then
	printf 'Runtime absence guard accepted a planted binary marker\n' >&2
	exit 1
fi
grep -q 'retired Apple TV runtime references' "$root/result"
printf 'Runtime absence negative checks passed.\n'
