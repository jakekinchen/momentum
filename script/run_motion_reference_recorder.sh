#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
EXERCISE_ID="${2:-${CAMIFIT_CAPTURE_EXERCISE_ID:-bodyweight_pushup}}"
APP_NAME="MotionReferenceRecorder"
DISPLAY_NAME="Motion Reference Recorder"
BUNDLE_ID="com.camifit.motion-reference-recorder"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

case "$MODE" in
  bodyweight_*)
    EXERCISE_ID="$MODE"
    MODE="run"
    ;;
esac

for process_name in "$APP_NAME" "$DISPLAY_NAME"; do
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
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

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
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSCameraUsageDescription</key>
  <string>CamiFit records a short local trainer reference video for MediaPipe pose extraction.</string>
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

open_app() {
  CAMIFIT_REPO_ROOT="$ROOT_DIR" \
    CAMIFIT_CAPTURE_EXERCISE_ID="$EXERCISE_ID" \
    /usr/bin/open -n \
      --env "CAMIFIT_REPO_ROOT=$ROOT_DIR" \
      --env "CAMIFIT_CAPTURE_EXERCISE_ID=$EXERCISE_ID" \
      "$APP_BUNDLE"
}

sign_app_bundle

case "$MODE" in
  run)
    open_app
    ;;
  --verify|verify)
    open_app
    sleep 3
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --debug|debug)
    CAMIFIT_REPO_ROOT="$ROOT_DIR" CAMIFIT_CAPTURE_EXERCISE_ID="$EXERCISE_ID" lldb -- "$APP_BINARY"
    ;;
  *)
    echo "usage: $0 [run|--verify|--debug|bodyweight_squat|bodyweight_pushup|bodyweight_lunge|bodyweight_plank] [exercise_id]" >&2
    exit 2
    ;;
esac
