#!/bin/sh

set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
options="$repo_root/Config/AppStoreExportOptions.plist"
options_json="$(mktemp)"
trap 'rm -f "$options_json"' EXIT HUP INT TERM

plutil -convert json -o "$options_json" "$options"

ruby -rjson -ryaml -e '
  options = JSON.parse(File.read(ARGV.fetch(0)))
  expected = {
    "destination" => "export",
    "generateAppStoreInformation" => false,
    "manageAppVersionAndBuildNumber" => false,
    "method" => "app-store-connect",
    "signingStyle" => "automatic",
    "uploadSymbols" => true,
  }
  abort "App Store export options do not match the local-only policy" unless
    options == expected

  project = YAML.safe_load(File.read(ARGV.fetch(1)), aliases: false)
  archive = project.dig("schemes", "MediaControlRelay", "archive")
  abort "MediaControlRelay archive action must use AppStore configuration" unless
    archive == { "config" => "AppStore" }
' "$options_json" "$repo_root/project.yml"
