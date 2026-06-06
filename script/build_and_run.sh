#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CamiFitApp"
DISPLAY_NAME="Future Coach"
BUNDLE_ID="com.camifit.app"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/Sources/CamiFitApp/Resources/Brand/future.svg"
ICON_GENERATOR="$ROOT_DIR/scripts/generate_future_app_icon.swift"
ICON_FILE="$APP_RESOURCES/AppIcon.icns"

for process_name in "$APP_NAME" "CamiFit" "$DISPLAY_NAME"; do
  while IFS= read -r app_pid; do
    [[ -n "$app_pid" ]] || continue
    pkill -TERM -P "$app_pid" >/dev/null 2>&1 || true
  done < <(pgrep -x "$process_name" || true)
  pkill -x "$process_name" >/dev/null 2>&1 || true
done

cd "$ROOT_DIR"
swift build --disable-sandbox --product "$APP_NAME"
BUILD_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

for resource_bundle in CamiFit_CamiFitApp.bundle CamiFit_KGKit.bundle; do
  if [[ -d "$BUILD_DIR/$resource_bundle" ]]; then
    cp -R "$BUILD_DIR/$resource_bundle" "$APP_RESOURCES/"
  fi
done

for framework in "$BUILD_DIR"/*.framework; do
  [[ -e "$framework" ]] || continue
  cp -R "$framework" "$APP_FRAMEWORKS/"
done

for dylib in "$BUILD_DIR"/*.dylib; do
  [[ -e "$dylib" ]] || continue
  cp "$dylib" "$APP_FRAMEWORKS/"
done

if [[ -f "$ICON_SOURCE" && -f "$ICON_GENERATOR" ]]; then
  xcrun swift "$ICON_GENERATOR" --brand "$ICON_SOURCE" --output "$ICON_FILE"
fi

install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY" 2>/dev/null || true

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
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
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSCameraUsageDescription</key>
  <string>Future Coach uses the camera to track exercise form locally.</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

find_codesign_identity() {
  if [[ -n "${CAMIFIT_CODESIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$CAMIFIT_CODESIGN_IDENTITY"
    return 0
  fi

  local identities identity prefix
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  for prefix in "Apple Development:" "Mac Developer:" "Developer ID Application:" "Apple Distribution:"; do
    while IFS= read -r identity; do
      case "$identity" in
        "$prefix"*)
          printf '%s\n' "$identity"
          return 0
          ;;
      esac
    done < <(printf '%s\n' "$identities" | sed -nE 's/^[[:space:]]*[0-9]+\) [A-Fa-f0-9]+ "([^"]+)".*/\1/p')
  done

  return 1
}

sign_app_bundle() {
  local identity
  if identity="$(find_codesign_identity)"; then
    echo "codesigning $APP_BUNDLE with $identity"
    codesign --force --deep --sign "$identity" --identifier "$BUNDLE_ID" "$APP_BUNDLE"
    codesign --verify --deep --strict "$APP_BUNDLE"
  else
    echo "WARNING: no Apple code-signing identity found; using an ad-hoc signature." >&2
    echo "WARNING: macOS may ask for camera access again after each rebuild." >&2
    codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE" >/dev/null 2>&1 || true
  fi
}

sign_app_bundle

open_app() {
  local open_env_args=(--env "CAMIFIT_REPO_ROOT=${CAMIFIT_REPO_ROOT:-$ROOT_DIR}")
  for env_name in \
    CAMIFIT_SYNTHETIC \
    CAMIFIT_SYNTHETIC_EXERCISE \
    CAMIFIT_SHOT_DIR \
    CAMIFIT_PYTHON \
    CAMIFIT_FRAME_DIR \
    CAMIFIT_GUIDE_EXERCISE \
    CAMIFIT_GUIDE_FRAME_MS
  do
    if env_value="$(printenv "$env_name")"; then
      open_env_args+=(--env "$env_name=$env_value")
    fi
  done
  if [[ ${#open_env_args[@]} -gt 0 ]]; then
    /usr/bin/open -n "${open_env_args[@]}" "$APP_BUNDLE"
  else
    /usr/bin/open -n "$APP_BUNDLE"
  fi
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 3
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
