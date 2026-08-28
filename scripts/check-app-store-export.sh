#!/bin/sh

set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
export_options="$repo_root/Config/AppStoreExportOptions.plist"
validation_options="$repo_root/Config/AppStoreValidationOptions.plist"
export_json="$(mktemp)"
validation_json="$(mktemp)"
trap 'rm -f "$export_json" "$validation_json"' EXIT HUP INT TERM

plutil -convert json -o "$export_json" "$export_options"
plutil -convert json -o "$validation_json" "$validation_options"

ruby -rjson -ryaml -e '
  export_options = JSON.parse(File.read(ARGV.fetch(0)))
  expected_export = {
    "destination" => "export",
    "generateAppStoreInformation" => false,
    "manageAppVersionAndBuildNumber" => false,
    "method" => "app-store-connect",
    "signingStyle" => "automatic",
    "uploadSymbols" => true,
  }
  abort "App Store export options do not match the local-only policy" unless
    export_options == expected_export

  validation_options = JSON.parse(File.read(ARGV.fetch(1)))
  expected_validation = {
    "destination" => "upload",
    "manageAppVersionAndBuildNumber" => false,
    "method" => "validation",
    "signingStyle" => "automatic",
  }
  abort "App Store validation options do not match the validation policy" unless
    validation_options == expected_validation

  project = YAML.safe_load(File.read(ARGV.fetch(2)), aliases: false)
  archive = project.dig("schemes", "MediaControlRelay", "archive")
  abort "MediaControlRelay archive action must use AppStore configuration" unless
    archive == { "config" => "AppStore" }
' "$export_json" "$validation_json" "$repo_root/project.yml"
