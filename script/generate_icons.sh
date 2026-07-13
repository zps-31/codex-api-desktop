#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDERER="$ROOT/script/render_app_icon.swift"

generate_icon() {
  local kind="$1"
  local resources="$2"
  local master="$resources/AppIcon.png"
  local temp
  local iconset
  temp="$(mktemp -d "${TMPDIR:-/tmp}/codex-icon.XXXXXX")"
  iconset="$temp/AppIcon.iconset"
  mkdir -p "$iconset" "$resources"

  xcrun swift "$RENDERER" "$kind" "$master"
  for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" "$master" \
      --out "$iconset/icon_${size}x${size}.png" >/dev/null
    local doubled=$((size * 2))
    /usr/bin/sips -z "$doubled" "$doubled" "$master" \
      --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  /usr/bin/iconutil -c icns "$iconset" -o "$resources/AppIcon.icns"
  rm -rf "$temp"
}

generate_icon api "$ROOT/Resources"
generate_icon meter "$ROOT/meter/Resources"
echo "Created application icons"
