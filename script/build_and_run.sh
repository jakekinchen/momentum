#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
CONFIGURATION="${CAMIFIT_BUILD_CONFIGURATION:-debug}"
DISTRIBUTION_CHANNEL="${CAMIFIT_DISTRIBUTION_CHANNEL:-local}"
APP_NAME="CamiFitApp"
APP_BUNDLE_NAME="${CAMIFIT_APP_BUNDLE_NAME:-Momentum}"
DISPLAY_NAME="${CAMIFIT_DISPLAY_NAME:-Momentum - Your Future Coach}"
BUNDLE_ID="com.camifit.app"
TEAM_ID="${CAMIFIT_TEAM_ID:-BN58T9KR6C}"
MIN_SYSTEM_VERSION="26.0"
SHORT_VERSION="${CAMIFIT_SHORT_VERSION:-1.0}"
BUNDLE_VERSION="${CAMIFIT_BUNDLE_VERSION:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_BUNDLE_NAME.app"
INSTALL_DIR="${CAMIFIT_INSTALL_DIR:-/Applications}"
INSTALLED_APP_BUNDLE="$INSTALL_DIR/$APP_BUNDLE_NAME.app"
LAUNCH_APP_BUNDLE="$APP_BUNDLE"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/Sources/CamiFitApp/Resources/Brand/future.svg"
ICON_GENERATOR="$ROOT_DIR/scripts/generate_future_app_icon.swift"
ICON_FILE="$APP_RESOURCES/AppIcon.icns"
REPO_ROOT_MARKER="$APP_RESOURCES/CamiFitRepoRoot.txt"
POSE_WORKER_HELPER_NAME="camifit-pose-worker"
POSE_WORKER_HELPER_DIR="$APP_RESOURCES/$POSE_WORKER_HELPER_NAME"
POSE_WORKER_HELPER_EXE="$POSE_WORKER_HELPER_DIR/$POSE_WORKER_HELPER_NAME"

for process_name in "$APP_NAME" "$APP_BUNDLE_NAME" "CamiFit" "Momentum" "Future Coach" "$DISPLAY_NAME"; do
  while IFS= read -r app_pid; do
    [[ -n "$app_pid" ]] || continue
    pkill -TERM -P "$app_pid" >/dev/null 2>&1 || true
  done < <(pgrep -x "$process_name" || true)
  pkill -x "$process_name" >/dev/null 2>&1 || true
done

cd "$ROOT_DIR"
if [[ "$MODE" == "release" || "$MODE" == "--release" ]]; then
  CONFIGURATION="release"
  MODE="package"
  DISTRIBUTION_CHANNEL="${CAMIFIT_DISTRIBUTION_CHANNEL:-direct}"
fi

build_args=(--disable-sandbox --product "$APP_NAME")
if [[ "$CONFIGURATION" == "release" ]]; then
  build_args=(-c release "${build_args[@]}")
fi

swift build "${build_args[@]}"
BUILD_DIR="$(swift build "${build_args[@]}" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

for resource_bundle in CamiFit_CamiFitApp.bundle CamiFit_KGKit.bundle; do
  if [[ -d "$BUILD_DIR/$resource_bundle" ]]; then
    rm -rf "$APP_BUNDLE/$resource_bundle" "$APP_RESOURCES/$resource_bundle"
    cp -R "$BUILD_DIR/$resource_bundle" "$APP_RESOURCES/"
  fi
done

if [[ -d "$ROOT_DIR/pose_worker" ]]; then
  rm -rf "$APP_RESOURCES/pose_worker"
  cp -R "$ROOT_DIR/pose_worker" "$APP_RESOURCES/pose_worker"
fi
if [[ "$DISTRIBUTION_CHANNEL" == "direct" ]]; then
  rm -f "$REPO_ROOT_MARKER"
  pose_worker_helper_source="${CAMIFIT_POSE_WORKER_HELPER_SOURCE:-}"
  if [[ -z "$pose_worker_helper_source" ]]; then
    pose_worker_helper_source="$("$ROOT_DIR/scripts/build_pose_worker_helper.sh")"
  fi
  if [[ ! -x "$pose_worker_helper_source/$POSE_WORKER_HELPER_NAME" ]]; then
    echo "ERROR: pose worker helper executable missing: $pose_worker_helper_source/$POSE_WORKER_HELPER_NAME" >&2
    exit 1
  fi
  rm -rf "$POSE_WORKER_HELPER_DIR"
  cp -R "$pose_worker_helper_source" "$POSE_WORKER_HELPER_DIR"
else
  printf '%s\n' "$ROOT_DIR" > "$REPO_ROOT_MARKER"
fi

for framework in "$BUILD_DIR"/*.framework; do
  [[ -e "$framework" ]] || continue
  cp -R "$framework" "$APP_FRAMEWORKS/"
done

for dylib in "$BUILD_DIR"/*.dylib; do
  [[ -e "$dylib" ]] || continue
  cp "$dylib" "$APP_FRAMEWORKS/"
done

verify_packaged_resource() {
  local resource_path="$1"
  if [[ ! -f "$resource_path" ]]; then
    echo "ERROR: required packaged resource missing: $resource_path" >&2
    exit 1
  fi
}

verify_unbundled_resource() {
  local resource_path="$1"
  local reason="$2"
  if [[ -e "$resource_path" ]]; then
    echo "ERROR: blocked packaged resource present: $resource_path" >&2
    echo "Reason: $reason" >&2
    exit 1
  fi
}

verify_review_only_motion_demo() {
  local exercise_id="$1"
  local app_resource_bundle="$2"
  local trace_path="$app_resource_bundle/MotionDemos/$exercise_id.jsonl"
  local manifest_path="$app_resource_bundle/MotionDemos/$exercise_id.manifest.json"

  verify_packaged_resource "$trace_path"
  verify_packaged_resource "$manifest_path"
  python3 - "$exercise_id" "$manifest_path" <<'PY'
import json
import sys

exercise_id = sys.argv[1]
manifest_path = sys.argv[2]
manifest = json.load(open(manifest_path, encoding="utf-8"))
manifest_id = str(manifest.get("exercise_id") or "").strip()
if manifest_id and manifest_id != exercise_id:
    raise SystemExit(f"{manifest_path}: exercise_id {manifest_id!r} does not match {exercise_id!r}")

acceptance = str(manifest.get("acceptance_status") or "").strip().lower()
normalizer = str(manifest.get("normalizer_status") or "").strip().lower()
scope = str(manifest.get("packaging_scope") or "").strip().lower()
review_statuses = ("blocked", "pending", "rejected")
if acceptance.startswith(("accepted", "protected_golden")):
    raise SystemExit(f"{manifest_path}: review-only bundle unexpectedly has promotable acceptance_status={acceptance!r}")
if not acceptance.startswith(review_statuses):
    raise SystemExit(f"{manifest_path}: review-only bundle needs blocked/pending/rejected acceptance_status, got {acceptance!r}")
if normalizer and normalizer.startswith(("accepted", "protected_golden")):
    raise SystemExit(f"{manifest_path}: review-only bundle unexpectedly has promotable normalizer_status={normalizer!r}")
if scope and scope != "motion_review_gallery_demo_only":
    raise SystemExit(f"{manifest_path}: unexpected review-only packaging_scope={scope!r}")
PY
}

verify_packaged_resources() {
  local bundle="${1:-$APP_BUNDLE}"
  local resources="$bundle/Contents/Resources"
  local app_resource_bundle="$resources/CamiFit_CamiFitApp.bundle"
  local kg_resource_bundle="$resources/CamiFit_KGKit.bundle"
  if [[ ! -d "$app_resource_bundle" ]]; then
    echo "ERROR: required app resource bundle missing: $app_resource_bundle" >&2
    exit 1
  fi
  if [[ ! -d "$kg_resource_bundle" ]]; then
    echo "ERROR: required KGKit resource bundle missing: $kg_resource_bundle" >&2
    exit 1
  fi

  verify_packaged_resource "$app_resource_bundle/Brand/future.svg"
  verify_packaged_resource "$app_resource_bundle/Avatars/neutral_humanoid.glb"
  verify_packaged_resource "$kg_resource_bundle/Artifact/kg_artifact.v0.json"
  verify_packaged_resource "$resources/pose_worker/pose_worker.py"
  verify_packaged_resource "$resources/pose_worker/models/pose_landmarker_lite.task"
  verify_unbundled_resource \
    "$bundle/CamiFit_CamiFitApp.bundle" \
    "macOS code signing rejects unsealed SwiftPM resource bundles in the .app bundle root"
  verify_unbundled_resource \
    "$bundle/CamiFit_KGKit.bundle" \
    "macOS code signing rejects unsealed SwiftPM resource bundles in the .app bundle root"

  if [[ "$DISTRIBUTION_CHANNEL" == "direct" ]]; then
    local pose_worker_helper_exe="$resources/$POSE_WORKER_HELPER_NAME/$POSE_WORKER_HELPER_NAME"
    verify_packaged_resource "$pose_worker_helper_exe"
    if [[ ! -x "$pose_worker_helper_exe" ]]; then
      echo "ERROR: packaged pose worker helper is not executable: $pose_worker_helper_exe" >&2
      exit 1
    fi
    local health
    health="$(printf '{"type":"health"}\n' | "$pose_worker_helper_exe" --mode mediapipe --model "$resources/pose_worker/models/pose_landmarker_lite.task")"
    if [[ "$health" != *'"pose_ready":true'* ]]; then
      echo "ERROR: packaged pose worker helper health check failed:" >&2
      echo "$health" >&2
      exit 1
    fi
  fi

  local exercise_id
  for exercise_id in bodyweight_squat bodyweight_lunge bodyweight_pushup single_arm_cable_tricep_extension standing_miniband_hip_flexion; do
    verify_packaged_resource "$app_resource_bundle/Presets/$exercise_id.json"
    verify_packaged_resource "$app_resource_bundle/MotionDemos/$exercise_id.jsonl"
    verify_packaged_resource "$app_resource_bundle/MotionDemos/$exercise_id.manifest.json"
  done

  verify_unbundled_resource \
    "$app_resource_bundle/Presets/bodyweight_jumping_jack.json" \
    "bodyweight_jumping_jack has been user-rejected and must not ship as an app preset until a clean external reference is accepted"
  verify_review_only_motion_demo bodyweight_jumping_jack "$app_resource_bundle"

  for exercise_id in bodyweight_pike bodyweight_plank resistance_band_reverse_curl bench_lying_single_arm_dumbbell_tricep_extension single_arm_dumbbell_preacher_curl wide_grip_preacher_curl_with_ez_bar single_arm_chest_supported_incline_row machine_chest_supported_row suspension_tricep_press; do
    verify_packaged_resource "$app_resource_bundle/Presets/$exercise_id.json"
    verify_review_only_motion_demo "$exercise_id" "$app_resource_bundle"
  done
}

verify_packaged_resources

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
  <key>CFBundleShortVersionString</key>
  <string>$SHORT_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUNDLE_VERSION</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.healthcare-fitness</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSCameraUsageDescription</key>
  <string>Momentum - Your Future Coach uses the camera to track exercise form locally.</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

find_codesign_identity() {
  local owner="${CAMIFIT_CODESIGN_OWNER:-Jake Kinchen}"
  if [[ -n "${CAMIFIT_CODESIGN_IDENTITY:-}" ]]; then
    if [[ "$CAMIFIT_CODESIGN_IDENTITY" != *"$owner"* ]]; then
      echo "ERROR: explicit CAMIFIT_CODESIGN_IDENTITY does not match owner '$owner': $CAMIFIT_CODESIGN_IDENTITY" >&2
      return 1
    fi
    if [[ "$DISTRIBUTION_CHANNEL" == "direct" && "$CAMIFIT_CODESIGN_IDENTITY" != Developer\ ID\ Application:* ]]; then
      echo "ERROR: direct distribution requires a Developer ID Application identity, got: $CAMIFIT_CODESIGN_IDENTITY" >&2
      return 1
    fi
    if [[ "$DISTRIBUTION_CHANNEL" == "direct" && "$CAMIFIT_CODESIGN_IDENTITY" != *"($TEAM_ID)"* ]]; then
      echo "ERROR: direct distribution identity must belong to team $TEAM_ID, got: $CAMIFIT_CODESIGN_IDENTITY" >&2
      return 1
    fi
    printf '%s\n' "$CAMIFIT_CODESIGN_IDENTITY"
    return 0
  fi

  local identities identity prefix
  identities="$(security find-identity -v -p codesigning 2>/dev/null | sed -nE 's/^[[:space:]]*[0-9]+\) [A-Fa-f0-9]+ "([^"]+)".*/\1/p' || true)"

  local preferred_prefixes=()
  if [[ "$DISTRIBUTION_CHANNEL" == "direct" ]]; then
    preferred_prefixes=("Developer ID Application:")
  elif [[ "$CONFIGURATION" == "release" ]]; then
    preferred_prefixes=("Apple Distribution:" "Developer ID Application:" "Apple Development:" "Mac Developer:")
  else
    preferred_prefixes=("Apple Development:" "Mac Developer:" "Apple Distribution:" "Developer ID Application:")
  fi

  for prefix in "${preferred_prefixes[@]}"; do
    while IFS= read -r identity; do
      case "$identity" in
        "$prefix"*"${owner}"*)
          if [[ "$DISTRIBUTION_CHANNEL" == "direct" && "$identity" != *"($TEAM_ID)"* ]]; then
            continue
          fi
          printf '%s\n' "$identity"
          return 0
          ;;
      esac
    done < <(printf '%s\n' "$identities")
  done

  return 1
}

sign_app_bundle() {
  local identity
  if identity="$(find_codesign_identity)"; then
    echo "codesigning $APP_BUNDLE with $identity"
    local codesign_args=(--force --deep --sign "$identity" --identifier "$BUNDLE_ID")
    if [[ "$DISTRIBUTION_CHANNEL" == "direct" ]]; then
      sign_nested_code "$identity"
      codesign_args=(--force --sign "$identity" --identifier "$BUNDLE_ID" --options runtime --timestamp)
    fi
    codesign "${codesign_args[@]}" "$APP_BUNDLE"
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
  elif [[ "$DISTRIBUTION_CHANNEL" == "direct" ]]; then
    echo "ERROR: direct distribution requires a Developer ID Application certificate for ${CAMIFIT_CODESIGN_OWNER:-Jake Kinchen} ($TEAM_ID)." >&2
    echo "ERROR: install/create the certificate for Jake's Apple Developer account before running '$0 release'." >&2
    exit 1
  else
    echo "WARNING: no Apple code-signing identity found for ${CAMIFIT_CODESIGN_OWNER:-Jake Kinchen}; using an ad-hoc signature." >&2
    echo "WARNING: macOS may ask for camera access again after each rebuild." >&2
    codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE" >/dev/null 2>&1 || true
  fi
}

sign_nested_code() {
  local identity="$1"
  local sign_args=(--force --sign "$identity" --options runtime --timestamp)
  local path

  if [[ -d "$POSE_WORKER_HELPER_DIR" ]]; then
    while IFS= read -r -d '' path; do
      if file -b "$path" | grep -q "Mach-O"; then
        codesign "${sign_args[@]}" "$path"
      fi
    done < <(find "$POSE_WORKER_HELPER_DIR" -type f \( -perm -111 -o -name '*.dylib' -o -name '*.so' \) -print0)
  fi

  if [[ -d "$APP_FRAMEWORKS" ]]; then
    while IFS= read -r -d '' path; do
      codesign "${sign_args[@]}" "$path"
    done < <(find "$APP_FRAMEWORKS" -type d -name '*.framework' -prune -print0)
  fi
}

sign_app_bundle

install_app_bundle() {
  local tmp_bundle="$INSTALL_DIR/.$APP_BUNDLE_NAME.codex-install.$$"
  if [[ "$INSTALLED_APP_BUNDLE" != "$INSTALL_DIR/"*.app ]]; then
    echo "ERROR: refusing unexpected install path: $INSTALLED_APP_BUNDLE" >&2
    exit 1
  fi

  mkdir -p "$INSTALL_DIR"
  rm -rf "$tmp_bundle"
  ditto "$APP_BUNDLE" "$tmp_bundle"
  rm -rf "$INSTALLED_APP_BUNDLE"
  mv "$tmp_bundle" "$INSTALLED_APP_BUNDLE"
  verify_packaged_resources "$INSTALLED_APP_BUNDLE"
  LAUNCH_APP_BUNDLE="$INSTALLED_APP_BUNDLE"
  echo "installed $INSTALLED_APP_BUNDLE"
}

open_app() {
  local open_env_args=()
  local env_command=(/usr/bin/env)
  for env_name in \
    CAMIFIT_REPO_ROOT \
    CAMIFIT_SYNTHETIC \
    CAMIFIT_SYNTHETIC_EXERCISE \
    CAMIFIT_SHOT_DIR \
    CAMIFIT_PYTHON \
    CAMIFIT_FRAME_DIR \
    CAMIFIT_GUIDE_EXERCISE
  do
    if env_value="$(printenv "$env_name")"; then
      open_env_args+=(--env "$env_name=$env_value")
    fi
  done

  if [[ "${CAMIFIT_ALLOW_FIXED_GUIDE_FRAME:-0}" == "1" ]]; then
    if env_value="$(printenv CAMIFIT_GUIDE_FRAME_MS)"; then
      open_env_args+=(--env "CAMIFIT_GUIDE_FRAME_MS=$env_value")
    fi
  else
    env_command+=(-u CAMIFIT_GUIDE_FRAME_MS)
  fi

  if [[ ${#open_env_args[@]} -gt 0 ]]; then
    "${env_command[@]}" /usr/bin/open -n "${open_env_args[@]}" "$LAUNCH_APP_BUNDLE"
  else
    "${env_command[@]}" /usr/bin/open -n "$LAUNCH_APP_BUNDLE"
  fi
}

case "$MODE" in
  package|--package)
    echo "$APP_BUNDLE"
    ;;
  install|--install)
    install_app_bundle
    ;;
  run)
    install_app_bundle
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    install_app_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    install_app_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    install_app_bundle
    open_app
    sleep 3
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|release|--package|--install|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
