#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/dist/releases"
VERSION="${MOMENTUM_RELEASE_VERSION:-${CAMIFIT_RELEASE_VERSION:-}}"
APP_BUNDLE_NAME="${MOMENTUM_RELEASE_APP_BUNDLE_NAME:-${CAMIFIT_RELEASE_APP_BUNDLE_NAME:-Momentum}}"
APP_DISPLAY_NAME="${MOMENTUM_RELEASE_APP_DISPLAY_NAME:-${CAMIFIT_RELEASE_APP_DISPLAY_NAME:-Momentum - Your Future Coach}}"
EXPECTED_BUNDLE_ID="${MOMENTUM_EXPECTED_BUNDLE_ID:-${CAMIFIT_EXPECTED_BUNDLE_ID:-com.camifit.app}}"
EXPECTED_SHORT_VERSION="${MOMENTUM_EXPECTED_SHORT_VERSION:-${CAMIFIT_EXPECTED_SHORT_VERSION:-1.0}}"
EXPECTED_BUNDLE_VERSION="${MOMENTUM_EXPECTED_BUNDLE_VERSION:-${CAMIFIT_EXPECTED_BUNDLE_VERSION:-}}"
APP_BUNDLE="${MOMENTUM_RELEASE_APP:-${CAMIFIT_RELEASE_APP:-$ROOT_DIR/dist/$APP_BUNDLE_NAME.app}}"
DMG_PATH="${MOMENTUM_RELEASE_DMG:-${CAMIFIT_RELEASE_DMG:-}}"
DOWNLOAD_URL="${MOMENTUM_DOWNLOAD_URL:-${CAMIFIT_DOWNLOAD_URL:-}}"
EXPECTED_SHA256="${MOMENTUM_EXPECTED_SHA256:-${CAMIFIT_EXPECTED_SHA256:-}}"

if [[ -z "$DMG_PATH" && -n "$VERSION" ]]; then
  DMG_PATH="$RELEASE_DIR/Momentum-macOS-$VERSION.dmg"
fi
if [[ -z "$DMG_PATH" ]]; then
  latest_dmg="$(ls -1t "$RELEASE_DIR"/Momentum-macOS-*.dmg 2>/dev/null | head -n 1 || true)"
  DMG_PATH="$latest_dmg"
fi

die() {
  echo "ERROR: $*" >&2
  exit 1
}

ok() {
  echo "ok: $*"
}

plist_read() {
  local key="$1"
  local plist="$2"
  /usr/libexec/PlistBuddy -c "Print :$key" "$plist" 2>/dev/null || true
}

require_file() {
  [[ -f "$1" ]] || die "missing file: $1"
}

require_dir() {
  [[ -d "$1" ]] || die "missing directory: $1"
}

require_executable() {
  [[ -x "$1" ]] || die "missing executable: $1"
}

validate_app_bundle() {
  local app="$1"
  local info executable display_name bundle_name bundle_id short_version bundle_version category helper model health

  require_dir "$app"
  info="$app/Contents/Info.plist"
  require_file "$info"

  display_name="$(plist_read CFBundleDisplayName "$info")"
  bundle_name="$(plist_read CFBundleName "$info")"
  executable="$(plist_read CFBundleExecutable "$info")"
  bundle_id="$(plist_read CFBundleIdentifier "$info")"
  short_version="$(plist_read CFBundleShortVersionString "$info")"
  bundle_version="$(plist_read CFBundleVersion "$info")"
  category="$(plist_read LSApplicationCategoryType "$info")"

  [[ "$display_name" == "$APP_DISPLAY_NAME" ]] || die "CFBundleDisplayName should be $APP_DISPLAY_NAME, got ${display_name:-<empty>}"
  [[ "$bundle_name" == "$APP_DISPLAY_NAME" ]] || die "CFBundleName should be $APP_DISPLAY_NAME, got ${bundle_name:-<empty>}"
  [[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || die "CFBundleIdentifier should be $EXPECTED_BUNDLE_ID, got ${bundle_id:-<empty>}"
  [[ "$short_version" == "$EXPECTED_SHORT_VERSION" ]] || die "CFBundleShortVersionString should be $EXPECTED_SHORT_VERSION, got ${short_version:-<empty>}"
  if [[ -z "$EXPECTED_BUNDLE_VERSION" && -n "$VERSION" ]]; then
    EXPECTED_BUNDLE_VERSION="${VERSION//-/.}"
  fi
  [[ -n "$bundle_version" ]] || die "CFBundleVersion is missing"
  if [[ -n "$EXPECTED_BUNDLE_VERSION" ]]; then
    [[ "$bundle_version" == "$EXPECTED_BUNDLE_VERSION" ]] || die "CFBundleVersion should be $EXPECTED_BUNDLE_VERSION, got ${bundle_version:-<empty>}"
  fi
  [[ "$category" == "public.app-category.healthcare-fitness" ]] || die "LSApplicationCategoryType should be public.app-category.healthcare-fitness, got ${category:-<empty>}"
  [[ -n "$executable" ]] || die "CFBundleExecutable is missing"
  require_executable "$app/Contents/MacOS/$executable"
  test ! -e "$app/Contents/Resources/CamiFitRepoRoot.txt" || die "release app contains repo-root marker"
  require_file "$app/Contents/Resources/AppIcon.icns"
  require_file "$app/Contents/Resources/CamiFit_CamiFitApp.bundle/Brand/future.svg"
  require_file "$app/Contents/Resources/CamiFit_CamiFitApp.bundle/Avatars/neutral_humanoid.glb"
  require_file "$app/Contents/Resources/CamiFit_KGKit.bundle/Artifact/kg_artifact.v0.json"
  test ! -e "$app/CamiFit_CamiFitApp.bundle" || die "release app contains unsealed CamiFit_CamiFitApp.bundle at app root"
  test ! -e "$app/CamiFit_KGKit.bundle" || die "release app contains unsealed CamiFit_KGKit.bundle at app root"

  helper="$app/Contents/Resources/camifit-pose-worker/camifit-pose-worker"
  model="$app/Contents/Resources/pose_worker/models/pose_landmarker_lite.task"
  require_executable "$helper"
  require_file "$model"
  health="$(printf '{"type":"health"}\n' | "$helper" --mode mediapipe --model "$model")"
  [[ "$health" == *'"pose_ready":true'* ]] || die "pose worker health check failed: $health"

  codesign --verify --verbose=2 "$app" >/dev/null
  xcrun stapler validate -v "$app" >/dev/null
  spctl -a -vv "$app" >/dev/null
  ok "validated app bundle $app"
}

validate_dmg() {
  local mount_dir attach_log mounted_device mounted_mount applications_target mounted_app

  require_file "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH" >/dev/null
  xcrun stapler validate -v "$DMG_PATH" >/dev/null
  spctl -a -vv -t open --context context:primary-signature "$DMG_PATH" >/dev/null

  mount_dir="$(mktemp -d)"
  attach_log="$(mktemp)"
  hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$mount_dir" >"$attach_log"
  mounted_device="$(awk '/^\/dev\/disk[0-9]+/ { print $1; exit }' "$attach_log")"
  mounted_mount="$(awk -v mount="$mount_dir" '$0 ~ mount { print $NF; exit }' "$attach_log")"
  rm -f "$attach_log"
  if [[ -z "$mounted_device" || -z "$mounted_mount" ]]; then
    [[ -n "$mounted_device" ]] && hdiutil detach "$mounted_device" >/dev/null 2>&1 || true
    rm -rf "$mount_dir"
    die "failed to mount DMG at expected mountpoint"
  fi

  mounted_app="$mount_dir/$APP_BUNDLE_NAME.app"
  require_dir "$mounted_app"
  test -e "$mount_dir/Applications" || {
    hdiutil detach "$mounted_device" >/dev/null 2>&1 || true
    rm -rf "$mount_dir"
    die "DMG is missing Applications drop target"
  }
  applications_target="$(readlink "$mount_dir/Applications" || true)"
  [[ "$applications_target" == "/Applications" ]] || {
    hdiutil detach "$mounted_device" >/dev/null 2>&1 || true
    rm -rf "$mount_dir"
    die "DMG Applications target should be /Applications, got ${applications_target:-<not a symlink>}"
  }
  validate_app_bundle "$mounted_app"

  hdiutil detach "$mounted_device" >/dev/null
  rm -rf "$mount_dir"
  ok "validated DMG $DMG_PATH"
}

validate_download_url() {
  local tmp downloaded_sha local_sha

  [[ -n "$DOWNLOAD_URL" ]] || {
    ok "skipped live download URL check; set MOMENTUM_DOWNLOAD_URL to enable it"
    return 0
  }
  [[ "${MOMENTUM_SKIP_DOWNLOAD_CHECK:-${CAMIFIT_SKIP_DOWNLOAD_CHECK:-0}}" != "1" ]] || {
    ok "skipped live download URL check by MOMENTUM_SKIP_DOWNLOAD_CHECK=1"
    return 0
  }

  tmp="$(mktemp -d)"
  curl \
    --fail \
    --location \
    --silent \
    --show-error \
    --user-agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15" \
    "$DOWNLOAD_URL" \
    --output "$tmp/download.dmg"
  downloaded_sha="$(shasum -a 256 "$tmp/download.dmg" | awk '{ print $1 }')"

  if [[ -n "$EXPECTED_SHA256" ]]; then
    [[ "$downloaded_sha" == "$EXPECTED_SHA256" ]] || die "download SHA mismatch: got $downloaded_sha expected $EXPECTED_SHA256"
  elif [[ -n "$DMG_PATH" && -f "$DMG_PATH" ]]; then
    local_sha="$(shasum -a 256 "$DMG_PATH" | awk '{ print $1 }')"
    [[ "$downloaded_sha" == "$local_sha" ]] || die "download SHA mismatch: got $downloaded_sha expected local $local_sha"
  fi

  rm -rf "$tmp"
  ok "validated live download $DOWNLOAD_URL"
}

validate_app_bundle "$APP_BUNDLE"
validate_dmg
validate_download_url
