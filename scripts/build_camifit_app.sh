#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$PWD"
APP="$REPO/dist/CamiFit.app"
BUNDLE_ID="com.camifit.app"
swift build --disable-sandbox --product CamiFitApp >/dev/null
BIN="$(swift build --disable-sandbox --product CamiFitApp --show-bin-path)"
pkill -x CamiFit 2>/dev/null || true; sleep 0.3
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/CamiFitApp" "$APP/Contents/MacOS/CamiFit"; chmod +x "$APP/Contents/MacOS/CamiFit"
# SwiftPM resource bundle must sit next to the binary so Bundle.module resolves.
for b in "$BIN"/*CamiFitApp*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/MacOS/"; done
for f in "$BIN"/*.framework; do [ -e "$f" ] && cp -R "$f" "$APP/Contents/Frameworks/"; done
for d in "$BIN"/*.dylib; do [ -e "$d" ] && cp "$d" "$APP/Contents/Frameworks/"; done
# Bundle the *native* Codex binary (not the node shim) so the GUI app can drive
# `codex app-server` without node or the user's PATH. ~200MB; notarize for distribution.
NATIVE_CODEX="$(node -e '
  const path=require("path"),{existsSync,realpathSync}=require("fs"),{createRequire}=require("module"),cp=require("child_process");
  let shim; try{ shim=realpathSync(cp.execSync("command -v codex",{shell:"/bin/bash"}).toString().trim()); }catch(e){ process.exit(1); }
  const {platform,arch}=process;
  const triple = platform!=="darwin" ? "" : (arch==="arm64"?"aarch64-apple-darwin":"x86_64-apple-darwin");
  const pkg = {"aarch64-apple-darwin":"@openai/codex-darwin-arm64","x86_64-apple-darwin":"@openai/codex-darwin-x64"}[triple];
  try{
    const root=path.dirname(createRequire(shim).resolve(pkg+"/package.json"));
    for(const c of [path.join(root,"vendor",triple,"bin","codex"), path.join(root,"vendor",triple,"codex","codex")])
      if(existsSync(c)){ console.log(c); process.exit(0); }
  }catch(e){}
  process.exit(1);
' 2>/dev/null || true)"
if [ -n "$NATIVE_CODEX" ] && [ -f "$NATIVE_CODEX" ]; then
  cp "$NATIVE_CODEX" "$APP/Contents/MacOS/codex"; chmod +x "$APP/Contents/MacOS/codex"
  echo "bundled native codex: $NATIVE_CODEX ($(du -h "$NATIVE_CODEX" | cut -f1))"
elif command -v codex >/dev/null 2>&1; then
  cp -L "$(command -v codex)" "$APP/Contents/MacOS/codex"; chmod +x "$APP/Contents/MacOS/codex"
  echo "WARNING: bundled the codex node shim (needs node at runtime); native binary not resolved"
else
  echo "(codex not found — app will look for a system codex at runtime)"
fi
[ -f /tmp/CamiFitAppIcon.icns ] && cp /tmp/CamiFitAppIcon.icns "$APP/Contents/Resources/AppIcon.icns" || true
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>CamiFit</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>CamiFit</string>
  <key>CFBundleDisplayName</key><string>CamiFit</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSCameraUsageDescription</key><string>CamiFit uses the camera to track your body pose and count exercise reps.</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
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
    echo "codesigning $APP with $identity"
    codesign --force --deep --sign "$identity" --identifier "$BUNDLE_ID" "$APP"
    codesign --verify --deep --strict "$APP"
  else
    echo "WARNING: no Apple code-signing identity found; using an ad-hoc signature." >&2
    echo "WARNING: macOS may ask for camera access again after each rebuild." >&2
    codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP" >/dev/null 2>&1 || echo "(codesign skipped)"
  fi
}

sign_app_bundle
echo "$APP"
open "$APP"
