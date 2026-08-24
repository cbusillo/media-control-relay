#!/bin/sh

set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"

command -v xcodegen >/dev/null 2>&1 || {
	printf 'xcodegen 2.40 or later is required\n' >&2
	exit 69
}

cd "$repo_root"
xcodegen generate --spec project.yml
