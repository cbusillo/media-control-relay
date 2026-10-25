#!/bin/sh

set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
cd "$repo_root"

for tool in rg python3; do
	command -v "$tool" >/dev/null 2>&1 || {
		printf '%s is required for public secret checks\n' "$tool" >&2
		exit 69
	}
done

exec python3 -I scripts/check-private-source.py
