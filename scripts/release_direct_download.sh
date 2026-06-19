#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/dist/releases"
VERSION="${MOMENTUM_RELEASE_VERSION:-${CAMIFIT_RELEASE_VERSION:-$(date -u +%Y%m%d%H%M%S)}}"
APP_BUNDLE_NAME="${MOMENTUM_RELEASE_APP_BUNDLE_NAME:-${CAMIFIT_RELEASE_APP_BUNDLE_NAME:-Momentum}}"
APP_DISPLAY_NAME="${MOMENTUM_RELEASE_APP_DISPLAY_NAME:-${CAMIFIT_RELEASE_APP_DISPLAY_NAME:-Momentum - Your Future Coach}}"
APP_BUNDLE="$ROOT_DIR/dist/$APP_BUNDLE_NAME.app"
ZIP_BASENAME="${MOMENTUM_RELEASE_ZIP_NAME:-${CAMIFIT_RELEASE_ZIP_NAME:-Momentum-macOS-$VERSION.zip}}"
DMG_BASENAME="${MOMENTUM_RELEASE_DMG_NAME:-${CAMIFIT_RELEASE_DMG_NAME:-Momentum-macOS-$VERSION.dmg}}"
NOTARY_ZIP="$RELEASE_DIR/notary-$ZIP_BASENAME"
FINAL_ZIP="$RELEASE_DIR/$ZIP_BASENAME"
FINAL_DMG="$RELEASE_DIR/$DMG_BASENAME"
DMG_BACKGROUND_SCRIPT="$ROOT_DIR/scripts/render_dmg_background.swift"
NOTARY_PROFILE="${MOMENTUM_NOTARY_PROFILE:-${CAMIFIT_NOTARY_PROFILE:-CamiFitNotary}}"
TEAM_ID="${MOMENTUM_TEAM_ID:-${CAMIFIT_TEAM_ID:-BN58T9KR6C}}"
OWNER="${MOMENTUM_CODESIGN_OWNER:-${CAMIFIT_CODESIGN_OWNER:-Jake Kinchen}}"
DMG_VOLUME_NAME="${MOMENTUM_DMG_VOLUME_NAME:-${CAMIFIT_DMG_VOLUME_NAME:-Momentum}}"
APP_SHORT_VERSION="${MOMENTUM_RELEASE_SHORT_VERSION:-${CAMIFIT_RELEASE_SHORT_VERSION:-1.0}}"
APP_BUNDLE_VERSION="${MOMENTUM_RELEASE_BUNDLE_VERSION:-${CAMIFIT_RELEASE_BUNDLE_VERSION:-${VERSION//-/.}}}"

mkdir -p "$RELEASE_DIR"

find_developer_id_identity() {
  local requested_identity
  requested_identity="${MOMENTUM_CODESIGN_IDENTITY:-${CAMIFIT_CODESIGN_IDENTITY:-}}"
  if [[ -n "$requested_identity" ]]; then
    if [[ "$requested_identity" != *"$OWNER"* ]]; then
      echo "ERROR: explicit MOMENTUM_CODESIGN_IDENTITY does not match owner '$OWNER': $requested_identity" >&2
      return 1
    fi
    if [[ "$requested_identity" != Developer\ ID\ Application:* ]]; then
      echo "ERROR: direct distribution requires a Developer ID Application identity, got: $requested_identity" >&2
      return 1
    fi
    if [[ "$requested_identity" != *"($TEAM_ID)"* ]]; then
      echo "ERROR: direct distribution identity must belong to team $TEAM_ID, got: $requested_identity" >&2
      return 1
    fi
    printf '%s\n' "$requested_identity"
    return 0
  fi

  security find-identity -v -p codesigning 2>/dev/null \
    | sed -nE 's/^[[:space:]]*[0-9]+\) [A-Fa-f0-9]+ "([^"]+)".*/\1/p' \
    | awk -v owner="$OWNER" -v team="($TEAM_ID)" '$0 ~ "^Developer ID Application:" && index($0, owner) && index($0, team) { print; exit }'
}

escape_applescript_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s\n' "$value"
}

configure_dmg_finder_window() {
  local volume_name app_item
  volume_name="$(escape_applescript_string "$1")"
  app_item="$(escape_applescript_string "$2")"

  osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$volume_name"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {180, 100, 900, 540}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 132
    set text size of theViewOptions to 13
    set background picture of theViewOptions to file ".background:installer-background.png"
    set position of item "$app_item" of container window to {188, 250}
    set position of item "Applications" of container window to {532, 250}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
}

create_drag_install_dmg() {
  local app_icon background_dir dmg_stage identity layout_dir rw_dmg attach_log mounted_device mounted_path volume_name
  dmg_stage="$(mktemp -d)"
  layout_dir="$(mktemp -d)"
  rw_dmg="$layout_dir/Momentum-layout.dmg"
  attach_log="$layout_dir/attach.log"
  rm -f "$FINAL_DMG"
  mkdir -p "$dmg_stage"
  cp -R "$APP_BUNDLE" "$dmg_stage/$APP_BUNDLE_NAME.app"
  ln -s /Applications "$dmg_stage/Applications"
  background_dir="$dmg_stage/.background"
  mkdir -p "$background_dir"

  app_icon="$APP_BUNDLE/Contents/Resources/AppIcon.icns"
  if [[ ! -f "$app_icon" ]]; then
    echo "ERROR: missing app icon for DMG background: $app_icon" >&2
    exit 1
  fi
  if [[ ! -f "$DMG_BACKGROUND_SCRIPT" ]]; then
    echo "ERROR: missing DMG background renderer: $DMG_BACKGROUND_SCRIPT" >&2
    exit 1
  fi
  echo "Rendering DMG installer background"
  xcrun swift "$DMG_BACKGROUND_SCRIPT" "$app_icon" "$background_dir/installer-background.png" "$APP_DISPLAY_NAME"

  echo "Creating drag-to-Applications DMG: $FINAL_DMG"
  hdiutil create \
    -volname "$DMG_VOLUME_NAME" \
    -srcfolder "$dmg_stage" \
    -format UDRW \
    -ov \
    "$rw_dmg"

  hdiutil attach "$rw_dmg" -nobrowse -readwrite >"$attach_log"
  mounted_device="$(awk -F '\t' '/^\/dev\/disk/ { device = $1; sub(/[[:space:]]+$/, "", device); print device; exit }' "$attach_log")"
  mounted_path="$(awk -F '\t' '/\/Volumes\// { print $NF; exit }' "$attach_log")"
  rm -f "$attach_log"
  if [[ -z "$mounted_device" || -z "$mounted_path" ]]; then
    echo "ERROR: failed to mount read-write DMG for Finder layout" >&2
    if [[ -n "$mounted_device" ]]; then
      hdiutil detach "$mounted_device" >/dev/null 2>&1 || true
    fi
    rm -rf "$dmg_stage" "$layout_dir"
    exit 1
  fi
  volume_name="${mounted_path##*/}"
  if ! configure_dmg_finder_window "$volume_name" "$APP_BUNDLE_NAME.app"; then
    echo "ERROR: failed to configure Finder layout for $FINAL_DMG" >&2
    hdiutil detach "$mounted_device" >/dev/null 2>&1 || true
    rm -rf "$dmg_stage" "$layout_dir"
    exit 1
  fi
  if ! hdiutil detach "$mounted_device"; then
    echo "ERROR: failed to detach layout DMG device $mounted_device" >&2
    rm -rf "$dmg_stage" "$layout_dir"
    exit 1
  fi
  hdiutil convert "$rw_dmg" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "${FINAL_DMG%.dmg}" >/dev/null

  rm -rf "$layout_dir"
  rm -rf "$dmg_stage"

  identity="$(find_developer_id_identity)"
  if [[ -z "$identity" ]]; then
    echo "ERROR: direct DMG distribution requires a Developer ID Application certificate for $OWNER." >&2
    exit 1
  fi
  echo "codesigning $FINAL_DMG with $identity"
  codesign --force --sign "$identity" --timestamp "$FINAL_DMG"
  codesign --verify --verbose=2 "$FINAL_DMG"
}

echo "Building direct-download app bundle for $OWNER"
CAMIFIT_DISTRIBUTION_CHANNEL=direct \
CAMIFIT_CODESIGN_OWNER="$OWNER" \
CAMIFIT_APP_BUNDLE_NAME="$APP_BUNDLE_NAME" \
CAMIFIT_DISPLAY_NAME="$APP_DISPLAY_NAME" \
CAMIFIT_SHORT_VERSION="$APP_SHORT_VERSION" \
CAMIFIT_BUNDLE_VERSION="$APP_BUNDLE_VERSION" \
  "$ROOT_DIR/script/build_and_run.sh" release

echo "Creating notarization zip: $NOTARY_ZIP"
rm -f "$NOTARY_ZIP" "$FINAL_ZIP" "$FINAL_DMG"
ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"

echo "Submitting to Apple notary service with profile '$NOTARY_PROFILE'"
xcrun notarytool submit "$NOTARY_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --team-id "$TEAM_ID" \
  --wait

echo "Stapling and validating ticket"
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate -v "$APP_BUNDLE"
spctl -a -vv "$APP_BUNDLE"

echo "Creating stapled release zip: $FINAL_ZIP"
ditto -c -k --keepParent "$APP_BUNDLE" "$FINAL_ZIP"
shasum -a 256 "$FINAL_ZIP"

create_drag_install_dmg

echo "Submitting DMG to Apple notary service with profile '$NOTARY_PROFILE'"
xcrun notarytool submit "$FINAL_DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --team-id "$TEAM_ID" \
  --wait

echo "Stapling and validating DMG ticket"
xcrun stapler staple "$FINAL_DMG"
xcrun stapler validate -v "$FINAL_DMG"
spctl -a -vv -t open --context context:primary-signature "$FINAL_DMG"
shasum -a 256 "$FINAL_DMG"

if [[ "${MOMENTUM_SKIP_RELEASE_SMOKE:-${CAMIFIT_SKIP_RELEASE_SMOKE:-0}}" != "1" ]]; then
  echo "Running extracted release smoke"
  smoke_dir="$(mktemp -d)"
  trap 'rm -rf "$smoke_dir"' EXIT
  ditto -x -k "$FINAL_ZIP" "$smoke_dir"
  smoke_app="$smoke_dir/$APP_BUNDLE_NAME.app"
  smoke_helper="$smoke_app/Contents/Resources/camifit-pose-worker/camifit-pose-worker"
  smoke_model="$smoke_app/Contents/Resources/pose_worker/models/pose_landmarker_lite.task"
  test ! -e "$smoke_app/Contents/Resources/CamiFitRepoRoot.txt"
  test -f "$smoke_app/Contents/Resources/CamiFit_CamiFitApp.bundle/Brand/future.svg"
  test -f "$smoke_app/Contents/Resources/CamiFit_CamiFitApp.bundle/Avatars/neutral_humanoid.glb"
  test -f "$smoke_app/Contents/Resources/CamiFit_KGKit.bundle/Artifact/kg_artifact.v0.json"
  test ! -e "$smoke_app/CamiFit_CamiFitApp.bundle"
  test ! -e "$smoke_app/CamiFit_KGKit.bundle"
  xcrun stapler validate -v "$smoke_app"
  spctl -a -vv "$smoke_app"
  health="$(printf '{"type":"health"}\n' | "$smoke_helper" --mode mediapipe --model "$smoke_model")"
  if [[ "$health" != *'"pose_ready":true'* ]]; then
    echo "ERROR: extracted release pose worker health check failed:" >&2
    echo "$health" >&2
    exit 1
  fi

  echo "Running mounted DMG smoke"
  dmg_mount="$(mktemp -d)"
  dmg_attach_log="$(mktemp)"
  hdiutil attach "$FINAL_DMG" -nobrowse -readonly -mountpoint "$dmg_mount" >"$dmg_attach_log"
  dmg_device="$(awk '/^\/dev\/disk[0-9]+[[:space:]]/ { print $1; exit }' "$dmg_attach_log")"
  dmg_mounted_device="$(awk -v mount="$dmg_mount" '$0 ~ mount { print $1; exit }' "$dmg_attach_log")"
  rm -f "$dmg_attach_log"
  if [[ -z "$dmg_device" ]]; then
    echo "ERROR: failed to find mounted DMG device for $FINAL_DMG" >&2
    rm -rf "$dmg_mount"
    exit 1
  fi
  trap 'if [[ -n "${dmg_device:-}" ]]; then hdiutil detach "$dmg_device" >/dev/null 2>&1 || true; fi; rm -rf "$smoke_dir" "$dmg_mount"' EXIT
  if [[ -z "$dmg_mounted_device" ]]; then
    echo "ERROR: failed to confirm DMG mountpoint for $FINAL_DMG" >&2
    exit 1
  fi
  test -d "$dmg_mount/$APP_BUNDLE_NAME.app"
  test -f "$dmg_mount/$APP_BUNDLE_NAME.app/Contents/Resources/CamiFit_CamiFitApp.bundle/Brand/future.svg"
  test -f "$dmg_mount/$APP_BUNDLE_NAME.app/Contents/Resources/CamiFit_CamiFitApp.bundle/Avatars/neutral_humanoid.glb"
  test -f "$dmg_mount/$APP_BUNDLE_NAME.app/Contents/Resources/CamiFit_KGKit.bundle/Artifact/kg_artifact.v0.json"
  test ! -e "$dmg_mount/$APP_BUNDLE_NAME.app/CamiFit_CamiFitApp.bundle"
  test ! -e "$dmg_mount/$APP_BUNDLE_NAME.app/CamiFit_KGKit.bundle"
  test -e "$dmg_mount/Applications"
  applications_target="$(readlink "$dmg_mount/Applications" || true)"
  if [[ "$applications_target" != "/Applications" ]]; then
    echo "ERROR: DMG Applications target must be a symlink to /Applications, got: ${applications_target:-<not a symlink>}" >&2
    exit 1
  fi
  xcrun stapler validate -v "$dmg_mount/$APP_BUNDLE_NAME.app"
  spctl -a -vv "$dmg_mount/$APP_BUNDLE_NAME.app"
  hdiutil detach "$dmg_device"
  dmg_device=""
fi

supabase_zip_dest="${MOMENTUM_SUPABASE_STORAGE_DEST:-${CAMIFIT_SUPABASE_STORAGE_DEST:-}}"
if [[ -n "$supabase_zip_dest" ]]; then
  echo "Uploading to Supabase Storage: $supabase_zip_dest"
  supabase storage cp "$FINAL_ZIP" "$supabase_zip_dest" \
    --content-type application/zip \
    --cache-control "max-age=300" \
    --yes
fi

supabase_dmg_dest="${MOMENTUM_SUPABASE_DMG_STORAGE_DEST:-${CAMIFIT_SUPABASE_DMG_STORAGE_DEST:-}}"
if [[ -n "$supabase_dmg_dest" ]]; then
  echo "Uploading DMG to Supabase Storage: $supabase_dmg_dest"
  supabase storage cp "$FINAL_DMG" "$supabase_dmg_dest" \
    --content-type application/x-apple-diskimage \
    --cache-control "max-age=300" \
    --yes
fi

echo "$FINAL_DMG"
