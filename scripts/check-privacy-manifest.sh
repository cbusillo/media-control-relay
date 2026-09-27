#!/bin/sh
# The privacy manifest must declare exactly the required-reason API categories
# that the shipped source uses. The source is the single source of truth; the
# built-app test checks that the bundle ships the manifest.

set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
manifest="$repo_root/Config/PrivacyInfo.xcprivacy"
sources="$repo_root/Sources"

# shellcheck disable=SC2016
declared="$(plutil -convert json -o - "$manifest" | ruby -rjson -e '
  manifest = JSON.parse($stdin.read)
  manifest.fetch("NSPrivacyAccessedAPITypes").each do |entry|
    puts entry.fetch("NSPrivacyAccessedAPIType")
  end
' | sort)"

used=''
if rg -q '\bUserDefaults\b' "$sources"; then
	used="$used
NSPrivacyAccessedAPICategoryUserDefaults"
fi
if rg -q 'ProcessInfo\.processInfo\.systemUptime|DispatchTime\.now\(\)\.uptimeNanoseconds' \
	"$sources"; then
	used="$used
NSPrivacyAccessedAPICategorySystemBootTime"
fi
used="$(printf '%s\n' "$used" | sed '/^$/d' | sort)"

[ "$declared" = "$used" ] || {
	printf '%s\n' \
		'PrivacyInfo.xcprivacy API categories do not match source usage.' \
		"Declared: $(printf '%s' "$declared" | tr '\n' ' ')" \
		"Used: $(printf '%s' "$used" | tr '\n' ' ')" >&2
	exit 1
}

undeclared_pattern='attributesOfItem|NSFileCreationDate|NSFileModificationDate|creationDateKey|contentModificationDateKey|volumeAvailableCapacity|systemFreeSize|activeInputModes|UITextInputMode'
if rg -n "$undeclared_pattern" "$sources"; then
	printf '%s\n' \
		'Potential undeclared required-reason API found; audit PrivacyInfo.xcprivacy' \
		>&2
	exit 1
fi
