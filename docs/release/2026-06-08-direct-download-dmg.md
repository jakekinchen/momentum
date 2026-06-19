# June 8 Direct Download DMG

**Release:** `macos-20260608-4`
**App bundle:** `dist/Momentum.app`
**Final DMG:** `dist/releases/Momentum-macOS-20260608-4.dmg`
**Stable GitHub asset:** `Momentum-macOS.dmg`

## Summary

The public website download was moved from a zip to a notarized
drag-to-Applications DMG. The visible installable bundle is `Momentum.app`.

The current public product display name is `Momentum - Your Future Coach`.

## Signing And Notarization

```text
Developer ID Application: Jake Kinchen (BN58T9KR6C)
App notary submission: 74b0904b-d62c-48c4-b200-ba68a321bd76
DMG notary submission: ec7aaa4a-f348-4d90-a284-070de17e569d
Notary status: Accepted
Gatekeeper source: Notarized Developer ID
```

## Artifact

```text
Size: 42,284,913 bytes
SHA-256: aa7dee5b3582a81a672c3714f16ab34d9647e6a0f12fbad6dd6965c8083e926a
GitHub release: https://github.com/jakekinchen/momentum/releases/tag/macos-20260608-4
Stable download: https://github.com/jakekinchen/momentum/releases/latest/download/Momentum-macOS.dmg
Live site download: https://momentum-future.vercel.app/download
```

## Verification

The stable GitHub download was fetched by `scripts/release_health_check.sh`
and matched the local DMG SHA-256.

```text
aa7dee5b3582a81a672c3714f16ab34d9647e6a0f12fbad6dd6965c8083e926a  dist/releases/Momentum-macOS-20260608-4.dmg
stable-github-dmg-matches-local
```

The downloaded DMG was validated with:

```bash
xcrun stapler validate -v dist/releases/Momentum-macOS-20260608-4.dmg
spctl -a -vv -t open --context context:primary-signature dist/releases/Momentum-macOS-20260608-4.dmg
```

Expected result:

```text
dist/releases/Momentum-macOS-20260608-4.dmg: accepted
source=Notarized Developer ID
origin=Developer ID Application: Jake Kinchen (BN58T9KR6C)
```

The downloaded DMG was also mounted and checked for:

```text
Momentum.app
Applications
CFBundleName => Momentum - Your Future Coach
CFBundleDisplayName => Momentum - Your Future Coach
```

The app inside the mounted DMG was accepted by Gatekeeper:

```text
/tmp/Momentum-site-dmg.../Momentum.app: accepted
source=Notarized Developer ID
origin=Developer ID Application: Jake Kinchen (BN58T9KR6C)
```

## Website Deployment

```text
Production deployment: https://momentum-future-95nuf52t9-jakebuddy7s-projects.vercel.app
Alias: https://momentum-future.vercel.app
Download redirect: https://github.com/jakekinchen/momentum/releases/latest/download/Momentum-macOS.dmg
```

Browser evidence:

```text
Production title: Momentum - Your Future Coach
Mobile title: Momentum - Your Future Coach
/download redirects to /download/mac in browser/curl fallback checks.
/download/mac says: Download Momentum for Mac
Installer window screenshot from 20260608-3 remains historical evidence only.
```
