#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build/cache
icon_work=$(mktemp -d "${TMPDIR:-/tmp}/clementine-icon.XXXXXX")
trap 'rm -rf "$icon_work"' EXIT
for variant in AppIcon AppIconLight; do
  icon_png="$icon_work/$variant.png"
  args=()
  if [[ "$variant" == "AppIconLight" ]]; then args=(--light); fi
  xcrun swift -module-cache-path .build/cache Scripts/generate-icon.swift "$icon_png" "${args[@]}"
  iconset="$icon_work/$variant.iconset"
  mkdir -p "$iconset"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$icon_png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$icon_png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  # Native multi-resolution encoding for both appearances.
  /usr/bin/iconutil -c icns "$iconset" -o "Resources/$variant.icns"
done
