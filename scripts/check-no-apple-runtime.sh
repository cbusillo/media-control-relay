#!/bin/sh
# All current distribution variants must remain independent of Apple TV helpers.
set -eu
app="${1:?Pass a built application bundle}"
[ -d "$app" ] && [ ! -L "$app" ] || exit 1
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
binary="$app/Contents/MacOS/$executable"
[ -f "$binary" ] || exit 1
# Capture first so a failed inspection cannot masquerade as an empty match.
symbols="$(nm -gU "$binary")"
undefined="$(nm -u "$binary")"
metadata="$(strings "$binary")"
if printf '%s\n%s\n%s\n' "$symbols" "$undefined" "$metadata" |
	rg -q 'AppleCompanion|RemoteControlRuntime|pyatv'; then
	printf 'Application still contains retired Apple TV runtime references\n' >&2
	exit 1
fi
material="$(find "$app" \( -name 'AppleCompanion*' -o -name 'apple-companion*' \
	-o -name '*.py' -o -name '*.pyc' -o -name '*.pyi' -o -name '*.pth' \
	-o -name '*.whl' -o -name '*.dist-info' -o -name 'site-packages' \
	-o -name 'pyvenv.cfg' -o -name 'libpython*' -o -name 'pyatv*' \) -print)"
[ -z "$material" ] || {
	printf 'Application contains retired helper or Python payload\n' >&2
	exit 1
}
printf 'Apple TV runtime absence verified.\n'
