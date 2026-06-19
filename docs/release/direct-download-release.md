# Direct Download Release

This is the public website distribution path for Momentum - Your Future Coach.

## Current Local Status

- The keychain has `Developer ID Application: Jake Kinchen (BN58T9KR6C)`.
- The Developer ID Application certificate was created on June 7, 2026 with
  Apple certificate ID `LSTJ33D4S3`.
- The certificate expires on June 8, 2031.
- `CamiFitNotary` is stored in Keychain and validated with notarytool.
- The current notarized drag-to-Applications DMG is
  `dist/releases/Momentum-macOS-20260608-4.dmg`.
- Current SHA-256:
  `aa7dee5b3582a81a672c3714f16ab34d9647e6a0f12fbad6dd6965c8083e926a`.
- Canonical public site:
  `https://momentum-future.vercel.app`.
- Public download URL:
  `https://github.com/jakekinchen/momentum/releases/latest/download/Momentum-macOS.dmg`.

Direct downloads outside the Mac App Store must be signed with a Developer ID
Application certificate, built with hardened runtime, notarized, and stapled.
Do not sign the public website bundle with Austen's account, and do not use
Jake's Apple Distribution certificate for this direct-download path.

## One-Time Setup

Create or import a Jake Developer ID Application certificate for the Apple
Developer team `BN58T9KR6C`, then confirm it appears locally.

```bash
security find-identity -p codesigning -v | rg "Developer ID Application: Jake Kinchen"
```

Store notary credentials in Keychain. Use Jake's Apple ID and an app-specific
password or an App Store Connect API key; do not put the secret in the repo.

```bash
xcrun notarytool store-credentials CamiFitNotary \
  --apple-id jakekinchen@gmail.com \
  --team-id BN58T9KR6C
```

GitHub Releases is the active public download host. Supabase Storage can remain
a mirror for small artifacts, but the bundled app can exceed Supabase Free-plan
object limits.

## Build, Notarize, And Upload

After the one-time setup, run:

```bash
MOMENTUM_RELEASE_VERSION=20260608-4 \
scripts/release_direct_download.sh
```

The script:

1. Builds `dist/Momentum.app` in release configuration.
2. Requires `Developer ID Application: Jake Kinchen`.
3. Signs with hardened runtime and a timestamp.
4. Submits an app zip to Apple's notary service.
5. Staples the ticket to the app bundle.
6. Creates a signed drag-to-Applications DMG containing `Momentum.app` and an
   `Applications` symlink.
7. Renders an installer background and writes Finder layout metadata so the DMG
   opens as a polished app-to-Applications install window.
8. Submits, staples, and validates the DMG.
9. Smoke-tests the extracted zip and mounted DMG by validating the stapled app
   and bundled pose worker health.

For direct distribution, `script/build_and_run.sh release` packages a
self-contained pose-worker helper. The helper is built with PyInstaller,
excludes drawing-only OpenCV/matplotlib/Pillow imports, and is checked for
`pose_ready:true` before signing. Direct releases must not include local
repo-root markers.

The public download URL shape is:

```text
https://github.com/jakekinchen/momentum/releases/latest/download/Momentum-macOS.dmg
```

Set that URL on Vercel so the website exposes the free Mac download:

```bash
MOMENTUM_RELEASE_VERSION=20260608-4 \
MOMENTUM_UPDATE_VERCEL_DOWNLOAD_URL=1 \
MOMENTUM_DEPLOY_WEBSITE=1 \
  scripts/publish_github_release_download.sh
```

## Verification

Run these checks before publishing the link:

```bash
MOMENTUM_RELEASE_VERSION=20260608-4 \
MOMENTUM_DOWNLOAD_URL="https://github.com/jakekinchen/momentum/releases/latest/download/Momentum-macOS.dmg" \
  scripts/release_health_check.sh

codesign --verify --deep --strict --verbose=2 dist/Momentum.app
xcrun stapler validate -v dist/Momentum.app
spctl -a -vv dist/Momentum.app
xcrun stapler validate -v dist/releases/Momentum-macOS-20260608-4.dmg
spctl -a -vv -t open --context context:primary-signature dist/releases/Momentum-macOS-20260608-4.dmg
```

Expected `spctl` result for the direct-download app is `accepted` with an
origin beginning with `Developer ID Application: Jake Kinchen`.

## June 8, 2026 Initial Evidence (Superseded)

```text
Developer ID Application: Jake Kinchen (BN58T9KR6C)
App notary submission: 0fb8778e-7032-4e22-9132-49b5576bf0ce
DMG notary submission: 47b3b362-420b-4bcc-b87e-18a0be3a2601
Notary status: Accepted
App bundle: dist/Momentum.app
Final DMG: dist/releases/Momentum-macOS-20260608-1.dmg
Size: 46,736,358 bytes
SHA-256: 878f73aac3e8f3d9991c561610a849e4ca7659a25f46e76b4931283d5e75f4df
GitHub stable asset: Momentum-macOS.dmg
GitHub release: https://github.com/jakekinchen/momentum/releases/tag/macos-20260608-1
Historical live site download: https://website-rho-one-42.vercel.app/download
Historical Vercel production deployment: https://website-8aet13ohy-jakebuddy7s-projects.vercel.app
Historical Vercel alias: https://website-rho-one-42.vercel.app
```

## June 8, 2026 Full-Brand DMG Evidence

```text
Developer ID Application: Jake Kinchen (BN58T9KR6C)
App notary submission: 74b0904b-d62c-48c4-b200-ba68a321bd76
DMG notary submission: ec7aaa4a-f348-4d90-a284-070de17e569d
Notary status: Accepted
App bundle: dist/Momentum.app
Display name: Momentum - Your Future Coach
Final DMG: dist/releases/Momentum-macOS-20260608-4.dmg
Size: 42,284,913 bytes
SHA-256: aa7dee5b3582a81a672c3714f16ab34d9647e6a0f12fbad6dd6965c8083e926a
GitHub stable asset: Momentum-macOS.dmg
GitHub release: https://github.com/jakekinchen/momentum/releases/tag/macos-20260608-4
Live site download: https://momentum-future.vercel.app/download
Vercel production deployment: https://momentum-future-95nuf52t9-jakebuddy7s-projects.vercel.app
Vercel alias: https://momentum-future.vercel.app
Mounted DMG bundle: Momentum.app
Mounted DMG CFBundleName: Momentum - Your Future Coach
Mounted DMG CFBundleDisplayName: Momentum - Your Future Coach
Mounted DMG Applications target: /Applications
Mobile download page verified 2026-06-08
```

## June 8, 2026 Polished DMG Evidence (Superseded)

```text
Developer ID Application: Jake Kinchen (BN58T9KR6C)
App notary submission: aa224e09-a468-4d21-a7bc-71cccd681d1b
DMG notary submission: 6378b39c-935d-4fe9-a83b-7a97008b225c
Notary status: Accepted
App bundle: dist/Momentum.app
Final DMG: dist/releases/Momentum-macOS-20260608-3.dmg
Size: 42,269,451 bytes
SHA-256: cae0539467b18e156cc7c4ef74f6535843b4caaa17e02d82ab3ec2152b6a6c44
GitHub stable asset: Momentum-macOS.dmg
GitHub release: https://github.com/jakekinchen/momentum/releases/tag/macos-20260608-3
Historical live site download: https://website-rho-one-42.vercel.app/download
Historical Vercel production deployment: https://website-l7qiawtmc-jakebuddy7s-projects.vercel.app
Historical Vercel alias: https://website-rho-one-42.vercel.app
Installer window screenshot: /tmp/momentum-dmg-window-20260608-3.png
Mobile download page screenshot: browser verification emitted 2026-06-08
Superseded because the bundle/display name was Momentum instead of
Momentum - Your Future Coach.
```

## June 7, 2026 Evidence

```text
Developer ID Application: Jake Kinchen (BN58T9KR6C)
Certificate ID: LSTJ33D4S3
Certificate SHA-1: DAD471316C2A62BBCB17BA6D8DCA7B8E5DFE1BC5
Notary submission: 92722e7e-6197-44ce-aef7-78b764001cfc
Notary status: Accepted
Gatekeeper source: Notarized Developer ID
Final zip: dist/releases/Momentum-macOS-20260607-4.zip
Size: 42,278,225 bytes
SHA-256: 7705bbe3d757940d8e5ba2c7a9fdb5dd9f1704b4c40303419175d2c8e4a22d3b
Supabase stable object: momentum-releases/Momentum-macOS.zip
Historical live site download: https://website-rho-one-42.vercel.app/download
```
