#!/bin/sh

set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
cd "$repo_root"

set -- .github/workflows
if [ -d .github/actions ]; then
	set -- "$@" .github/actions
fi

uses_lines="$({
	rg -n \
		--glob '*.yml' \
		--glob '*.yaml' \
		'^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]+' \
		"$@" || true
})"

if [ -z "$uses_lines" ]; then
	exit 0
fi

unpinned_lines="$({
	printf '%s\n' "$uses_lines" |
		rg -v --pcre2 \
			'uses:\s+\./|uses:\s+[^@\s]+@[0-9a-f]{40}(?:\s+#.*)?$' || true
})"

if [ -n "$unpinned_lines" ]; then
	printf '%s\n' \
		'GitHub Actions must use immutable 40-character commit SHAs:' \
		"$unpinned_lines" >&2
	exit 1
fi
