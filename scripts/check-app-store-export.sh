#!/bin/sh
# Local App Store exports must never upload. Uploads go only through the
# separate validation options, which an operator runs deliberately.

set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
export_options="$repo_root/Config/AppStoreExportOptions.plist"

destination="$(plutil -extract destination raw -o - "$export_options")"
[ "$destination" = "export" ] || {
	printf 'App Store export options must keep destination=export, found %s\n' \
		"$destination" >&2
	exit 1
}
