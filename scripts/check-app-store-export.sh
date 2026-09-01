#!/bin/sh

set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
export_options="$repo_root/Config/AppStoreExportOptions.plist"
validation_options="$repo_root/Config/AppStoreValidationOptions.plist"
app_store_entitlements="$repo_root/Config/MediaControlRelayAppStore.entitlements"
direct_entitlements="$repo_root/Config/MediaControlRelay.entitlements"
info_plist="$repo_root/Config/MediaControlRelay-Info.plist"
export_json="$(mktemp)"
validation_json="$(mktemp)"
app_store_entitlements_json="$(mktemp)"
direct_entitlements_json="$(mktemp)"
info_json="$(mktemp)"
trap 'rm -f "$export_json" "$validation_json" "$app_store_entitlements_json" "$direct_entitlements_json" "$info_json"' EXIT HUP INT TERM

plutil -convert json -o "$export_json" "$export_options"
plutil -convert json -o "$validation_json" "$validation_options"
plutil -convert json -o "$app_store_entitlements_json" "$app_store_entitlements"
plutil -convert json -o "$direct_entitlements_json" "$direct_entitlements"
plutil -convert json -o "$info_json" "$info_plist"

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

  direct_entitlements_path = project.dig(
    "targets", "MediaControlRelay", "settings", "base", "CODE_SIGN_ENTITLEMENTS"
  )
  abort "Direct builds must use the direct-build entitlement file" unless
    direct_entitlements_path == "Config/MediaControlRelay.entitlements"

  config_entitlement_overrides = project
    .dig("targets", "MediaControlRelay", "settings", "configs")
    .to_h
    .each_with_object({}) do |(config, settings), overrides|
      entitlements_path = settings.to_h["CODE_SIGN_ENTITLEMENTS"]
      overrides[config] = entitlements_path if entitlements_path
    end
  expected_config_entitlement_overrides = {
    "AppStore" => "Config/MediaControlRelayAppStore.entitlements",
  }
  abort "Only App Store builds may override the direct-build entitlement file" unless
    config_entitlement_overrides == expected_config_entitlement_overrides

  app_store_entitlements = JSON.parse(File.read(ARGV.fetch(3)))
  expected_app_store_entitlements = {
    "com.apple.security.app-sandbox" => true,
    "com.apple.security.network.client" => true,
    "com.apple.security.network.server" => true,
  }
  abort "App Store entitlements do not match the sandbox network policy" unless
    app_store_entitlements == expected_app_store_entitlements

  direct_entitlements = JSON.parse(File.read(ARGV.fetch(4)))
  abort "Direct builds must not declare application entitlements" unless
    direct_entitlements == {}
  info_plist = JSON.parse(File.read(ARGV.fetch(5)))
  expected_url_types = [
    {
      "CFBundleTypeRole" => "Viewer",
      "CFBundleURLName" => "com.shinycomputers.media-control-relay.external-volume",
      "CFBundleURLSchemes" => ["media-control-relay"],
    },
  ]
  abort "Info.plist must register exactly the media-control-relay URL scheme" unless
    info_plist["CFBundleURLTypes"] == expected_url_types
' "$export_json" "$validation_json" "$repo_root/project.yml" \
	"$app_store_entitlements_json" "$direct_entitlements_json" "$info_json"
