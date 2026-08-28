#!/bin/sh

set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
manifest="$repo_root/Config/PrivacyInfo.xcprivacy"
manifest_json="$(mktemp)"
trap 'rm -f "$manifest_json"' EXIT HUP INT TERM

plutil -convert json -o "$manifest_json" "$manifest"

ruby -rjson -ryaml -e '
  manifest = JSON.parse(File.read(ARGV.fetch(0)))
  expected_keys = %w[
    NSPrivacyAccessedAPITypes
    NSPrivacyCollectedDataTypes
    NSPrivacyTracking
    NSPrivacyTrackingDomains
  ].sort
  abort "privacy manifest has unexpected top-level keys" unless
    manifest.keys.sort == expected_keys
  abort "privacy manifest must disable tracking" unless
    manifest.fetch("NSPrivacyTracking") == false
  abort "privacy manifest must not declare tracking domains" unless
    manifest.fetch("NSPrivacyTrackingDomains") == []
  abort "privacy manifest must not declare collected data" unless
    manifest.fetch("NSPrivacyCollectedDataTypes") == []

  declarations = manifest.fetch("NSPrivacyAccessedAPITypes").map do |entry|
    expected_entry_keys = %w[
      NSPrivacyAccessedAPIType
      NSPrivacyAccessedAPITypeReasons
    ].sort
    abort "privacy API declaration has unexpected keys" unless
      entry.keys.sort == expected_entry_keys
    [
      entry.fetch("NSPrivacyAccessedAPIType"),
      entry.fetch("NSPrivacyAccessedAPITypeReasons").sort,
    ]
  end.sort_by(&:first)
  expected_declarations = [
    ["NSPrivacyAccessedAPICategorySystemBootTime", ["35F9.1"]],
    ["NSPrivacyAccessedAPICategoryUserDefaults", ["CA92.1"]],
  ]
  abort "privacy API declarations do not match audited source usage" unless
    declarations == expected_declarations

  project = YAML.safe_load(File.read(ARGV.fetch(1)), aliases: false)
  matches = project.fetch("targets").each_with_object([]) do |(target_name, target), result|
    Array(target["sources"]).each do |source|
      next unless source.is_a?(Hash)
      next unless source["path"] == "Config/PrivacyInfo.xcprivacy"
      result << [target_name, source["buildPhase"]]
    end
  end
  abort "privacy manifest must be an app-only resources-phase source" unless
    matches == [["MediaControlRelay", "resources"]]
' "$manifest_json" "$repo_root/project.yml"

rg -q '\bUserDefaults\b' "$repo_root/Sources" || {
	printf 'UserDefaults declaration is stale; update PrivacyInfo.xcprivacy\n' >&2
	exit 1
}
rg -q 'ProcessInfo\.processInfo\.systemUptime|DispatchTime\.now\(\)\.uptimeNanoseconds' \
	"$repo_root/Sources" || {
	printf 'SystemBootTime declaration is stale; update PrivacyInfo.xcprivacy\n' >&2
	exit 1
}

undeclared_pattern='attributesOfItem|NSFileCreationDate|NSFileModificationDate|creationDateKey|contentModificationDateKey|volumeAvailableCapacity|systemFreeSize|activeInputModes|UITextInputMode'
if rg -n "$undeclared_pattern" "$repo_root/Sources"; then
	printf '%s\n' \
		'Potential undeclared required-reason API found; audit PrivacyInfo.xcprivacy' \
		>&2
	exit 1
fi
