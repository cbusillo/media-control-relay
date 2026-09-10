#!/bin/sh
# Exercise the real verifier on a disposable copy, never the installed runtime.
set -eu
repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
candidate="$(mktemp -d "${TMPDIR:-/tmp}/mcr-metadata.XXXXXX")"
trap 'rm -rf "$candidate"' EXIT HUP INT TERM
cp -R "${1:?Pass a staged runtime}/." "$candidate/"
check="$repo_root/scripts/check-apple-companion-runtime.sh"
"$check" "$candidate" >/dev/null
printf 'Finder metadata\n' >"$candidate/.DS_Store"
printf 'Nested Finder metadata\n' >"$candidate/python/.DS_Store"
"$check" "$candidate" >/dev/null
# Real payload changes remain failures even with the ignored metadata present.
printf '\n# unexpected change\n' >>"$candidate/bin/apple-companion-helper"
if "$check" "$candidate" >/dev/null 2>&1; then
	printf 'Verifier accepted modified runtime payload\n' >&2
	exit 1
fi
cp "${1}/bin/apple-companion-helper" "$candidate/bin/apple-companion-helper"
rm "$candidate/.DS_Store"
ln -s bin/apple-companion-helper "$candidate/.DS_Store"
if "$check" "$candidate" >/dev/null 2>&1; then
	printf 'Verifier ignored a metadata-named symlink\n' >&2
	exit 1
fi
rm "$candidate/.DS_Store"
mkdir "$candidate/.DS_Store"
printf 'unexpected payload\n' >"$candidate/.DS_Store/payload"
if "$check" "$candidate" >/dev/null 2>&1; then
	printf 'Verifier ignored a metadata-named directory subtree\n' >&2
	exit 1
fi
printf 'Apple Companion Finder metadata regression checks passed.\n'
