#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CodexAPIManagerPlus"
DISPLAY_NAME="Codex API 桌面版 Plus"
BUNDLE_ID="com.zps.codex-api-desktop.plus"
APP_VERSION="2.14.5"
BUILD_NUMBER="33"
MIN_SYSTEM_VERSION="14.0"
ARCHS="${ARCHS:-arm64 x86_64}"
DISTRIBUTION="${DISTRIBUTION:-0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
APP_ICON="$ROOT_DIR/Resources/AppIcon.icns"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ARCHIVE_NAME="Codex-API-Desktop-Plus-$APP_VERSION.zip"
ARCHIVE_PATH="$DIST_DIR/$ARCHIVE_NAME"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"

read -r -a ARCH_LIST <<<"$ARCHS"

require_distribution_credentials() {
  if [[ "$DISTRIBUTION" != "1" ]]; then
    return 0
  fi
  if [[ "$SIGN_IDENTITY" == "-" || -z "$SIGN_IDENTITY" ]]; then
    echo "DISTRIBUTION=1 requires SIGN_IDENTITY for a Developer ID Application certificate" >&2
    exit 1
  fi
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "DISTRIBUTION=1 requires NOTARY_PROFILE for xcrun notarytool" >&2
    exit 1
  fi
}

release_build_args() {
  RELEASE_BUILD_ARGS=(-c release)
  local architecture
  for architecture in "${ARCH_LIST[@]}"; do
    RELEASE_BUILD_ARGS+=(--arch "$architecture")
  done
}

verify_architectures() {
  local binary="$1"
  local architecture
  for architecture in "${ARCH_LIST[@]}"; do
    /usr/bin/lipo -verify_arch "$architecture" "$binary"
  done
}

build_release() {
  release_build_args
  swift build "${RELEASE_BUILD_ARGS[@]}" -Xswiftc -warnings-as-errors
  BUILD_BINARY="$(swift build "${RELEASE_BUILD_ARGS[@]}" --show-bin-path)/$APP_NAME"
  verify_architectures "$BUILD_BINARY"
  "$BUILD_BINARY" --self-test
  if [[ "$(uname -m)" == "arm64" ]] && [[ " ${ARCH_LIST[*]} " == *" x86_64 "* ]]; then
    /usr/bin/arch -x86_64 "$BUILD_BINARY" --self-test
  fi
}

build_debug() {
  swift build -Xswiftc -warnings-as-errors
  BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"
}

terminate_running_managers() {
  local pid
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    kill -TERM "$pid" >/dev/null 2>&1 || true
  done < <(
    /usr/bin/pgrep -f "/Contents/MacOS/${APP_NAME}$" 2>/dev/null || true
  )

  local attempt
  for attempt in {1..40}; do
    if ! /usr/bin/pgrep -f "/Contents/MacOS/${APP_NAME}$" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done
  echo "Existing $APP_NAME process did not terminate" >&2
  return 1
}

create_bundle() {
  [[ -f "$APP_ICON" ]] || {
    echo "Missing application icon: $APP_ICON" >&2
    exit 1
  }
  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$BUILD_BINARY" "$APP_BINARY"
  cp "$APP_ICON" "$APP_RESOURCES/AppIcon.icns"
  chmod +x "$APP_BINARY"

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST
  /usr/bin/plutil -lint "$INFO_PLIST" >/dev/null

  if [[ "$DISTRIBUTION" == "1" ]]; then
    /usr/bin/codesign \
      --force \
      --options runtime \
      --timestamp \
      --sign "$SIGN_IDENTITY" \
      "$APP_BUNDLE"
  else
    /usr/bin/codesign --force --sign - "$APP_BUNDLE"
  fi
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
}

create_archive() {
  rm -f "$ARCHIVE_PATH" "$CHECKSUM_PATH"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE_PATH"
  /usr/bin/unzip -tq "$ARCHIVE_PATH" >/dev/null
}

notarize_distribution() {
  if [[ "$DISTRIBUTION" != "1" ]]; then
    return 0
  fi
  xcrun notarytool submit \
    "$ARCHIVE_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  /usr/sbin/spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
  create_archive
}

write_checksum() {
  (
    cd "$DIST_DIR"
    /usr/bin/shasum -a 256 "$ARCHIVE_NAME" >"$ARCHIVE_NAME.sha256"
    cat "$ARCHIVE_NAME.sha256"
  )
}

require_distribution_credentials
cd "$ROOT_DIR"
case "$MODE" in
  package)
    build_release
    create_bundle
    create_archive
    notarize_distribution
    write_checksum
    echo "Created: $APP_BUNDLE"
    echo "Created: $ARCHIVE_PATH"
    ;;
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
    if [[ "$DISTRIBUTION" == "1" ]]; then
      echo "DISTRIBUTION=1 is only supported with package mode" >&2
      exit 2
    fi
    build_debug
    create_bundle
    case "$MODE" in
      run)
        terminate_running_managers
        /usr/bin/open -n "$APP_BUNDLE"
        ;;
      --debug|debug)
        lldb -- "$APP_BINARY"
        ;;
      --logs|logs)
        /usr/bin/open -n "$APP_BUNDLE"
        /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
        ;;
      --telemetry|telemetry)
        /usr/bin/open -n "$APP_BUNDLE"
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
        ;;
      --verify|verify)
        "$APP_BINARY" --self-test
        ;;
    esac
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|package]" >&2
    exit 2
    ;;
esac
