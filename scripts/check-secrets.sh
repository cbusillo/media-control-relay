#!/bin/sh

set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
cd "$repo_root"

command -v rg >/dev/null 2>&1 || {
	printf 'ripgrep is required for public secret checks\n' >&2
	exit 69
}

forbidden_files="$(find . \
	-path './.git' -prune -o \
	-path './.build' -prune -o \
	-path './MediaControlRelay.xcodeproj' -prune -o \
	-path './scratch' -prune -o \
	-type f \( \
	-name '.env*' -o \
	-name '*.env' -o \
	-name '*.env.*' -o \
	-name '*.p8' -o \
	-name '*.p12' -o \
	-name '*.pem' -o \
	-name '*.key' -o \
	-name '*.cer' -o \
	-name '*.mobileprovision' -o \
	-name '*.provisionprofile' -o \
	-name 'samtvcli.yaml' \
\) -print)"

if [ -n "$forbidden_files" ]; then
	printf 'forbidden secret-bearing files found:\n%s\n' "$forbidden_files" >&2
	exit 1
fi

if rg -n --hidden \
	--glob '!.git/**' \
	--glob '!.build/**' \
	--glob '!MediaControlRelay.xcodeproj/**' \
	--glob '!scratch/**' \
	--glob '!scripts/check-secrets.sh' \
	'\b(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|169\.254\.[0-9]{1,3}\.[0-9]{1,3})\b|(?i:\.local\b)' .; then
	printf 'private network address found in public source\n' >&2
	exit 1
fi

printf 'Public secret checks passed.\n'
