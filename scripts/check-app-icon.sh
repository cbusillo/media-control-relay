#!/bin/sh

set -eu

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
iconset="$repo_root/Resources/AppIcon.iconset"
source_icon="$repo_root/Resources/AppIcon.icns"

command -v sips >/dev/null 2>&1 || {
	printf 'sips is required for app icon validation\n' >&2
	exit 69
}
command -v iconutil >/dev/null 2>&1 || {
	printf 'iconutil is required for app icon validation\n' >&2
	exit 69
}

ruby -ryaml -e '
  icon = ARGV.fetch(0)
  project = YAML.safe_load(File.read(ARGV.fetch(1)), aliases: false)
  abort "Missing generated AppIcon.icns" unless File.file?(icon)
  target = project.dig("targets", "MediaControlRelay")
  sources = target.fetch("sources")
  expected_source = { "path" => "Resources/AppIcon.icns", "buildPhase" => "resources" }
  abort "MediaControlRelay must include AppIcon.icns as a resource" unless
    sources.include?(expected_source)
' "$source_icon" "$repo_root/project.yml"

icon_specifications='16:icon_16x16.png
32:icon_16x16@2x.png
32:icon_32x32.png
64:icon_32x32@2x.png
128:icon_128x128.png
256:icon_128x128@2x.png
256:icon_256x256.png
512:icon_256x256@2x.png
512:icon_512x512.png
1024:icon_512x512@2x.png'

validate_iconset() {
	root="$1"
	for specification in $icon_specifications; do
		size="${specification%%:*}"
		filename="${specification#*:}"
		image="$root/$filename"
		width="$(sips -g pixelWidth "$image" 2>/dev/null | awk '/pixelWidth:/ { print $2 }')"
		height="$(sips -g pixelHeight "$image" 2>/dev/null | awk '/pixelHeight:/ { print $2 }')"
		format="$(sips -g format "$image" 2>/dev/null | awk '/format:/ { print $2 }')"
		[ "$width" = "$size" ] && [ "$height" = "$size" ] && [ "$format" = "png" ] || {
			printf 'Invalid AppIcon image: %s\n' "$image" >&2
			exit 1
		}
	done
}

validate_iconset "$iconset"

source_expanded="$(mktemp -d)"
trap 'rm -rf "$source_expanded"' EXIT HUP INT TERM
iconutil --convert iconset --output "$source_expanded/AppIcon.iconset" "$source_icon"
validate_iconset "$source_expanded/AppIcon.iconset"

[ "$#" -eq 0 ] && exit 0
[ "$#" -eq 1 ] || {
	printf 'usage: %s [built-app]\n' "$0" >&2
	exit 64
}

app="$1"
icon="$app/Contents/Resources/AppIcon.icns"
[ -f "$icon" ] || {
	printf 'Built app is missing AppIcon.icns\n' >&2
	exit 1
}
[ "$(plutil -extract CFBundleIconFile raw -o - "$app/Contents/Info.plist")" = "AppIcon" ] || {
	printf 'Built app does not declare AppIcon.icns\n' >&2
	exit 1
}
cmp -s "$source_icon" "$icon" || {
	printf 'Built AppIcon.icns differs from the repository icon\n' >&2
	exit 1
}

expanded="$(mktemp -d)"
trap 'rm -rf "$source_expanded" "$expanded"' EXIT HUP INT TERM
iconutil --convert iconset --output "$expanded/AppIcon.iconset" "$icon"
validate_iconset "$expanded/AppIcon.iconset"
