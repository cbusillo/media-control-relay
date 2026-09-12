#!/bin/sh
# All current distribution variants must remain independent of Apple TV helpers.
set -eu
app="${1:?Pass a built application bundle}"
[ -d "$app" ] && [ ! -L "$app" ] || {
	printf 'Expected a regular application directory\n' >&2
	exit 1
}
command -v rg >/dev/null 2>&1 || {
	printf 'ripgrep is required for runtime inspection\n' >&2
	exit 69
}
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
binary="$app/Contents/MacOS/$executable"
[ -f "$binary" ] || {
	printf 'Application executable is missing\n' >&2
	exit 1
}
lipo "$binary" -verify_arch arm64
# Current app targets embed no secondary executable; this symbol check covers
# the main executable, while the payload-name check traverses the whole bundle.
# Capture first so a failed inspection cannot masquerade as an empty match.
symbols="$(nm -gU "$binary")"
undefined="$(nm -u "$binary")"
metadata="$(strings "$binary")"
match_status=0
printf '%s\n%s\n%s\n' "$symbols" "$undefined" "$metadata" |
	rg -q 'AppleCompanion|RemoteControlRuntime|pyatv' || match_status=$?
case "$match_status" in
0)
	printf 'Application still contains retired Apple TV runtime references\n' >&2
	exit 1
	;;
1) ;;
*)
	printf 'Runtime symbol inspection failed\n' >&2
	exit "$match_status"
	;;
esac
material="$(find "$app" \( -name 'AppleCompanion*' -o -name 'apple-companion*' \
	-o -name '*.py' -o -name '*.pyc' -o -name '*.pyi' -o -name '*.pth' \
	-o -name '*.whl' -o -name '*.dist-info' -o -name 'site-packages' \
	-o -name 'pyvenv.cfg' -o -name 'libpython*' -o -name 'pyatv*' \) -print)"
[ -z "$material" ] || {
	printf 'Application contains retired helper or Python payload\n' >&2
	exit 1
}
printf 'Apple TV runtime absence verified.\n'
