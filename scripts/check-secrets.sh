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
	-path '*/.venv' -prune -o \
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

python3 scripts/check-private-source.py

printf 'Public secret checks passed.\n'
