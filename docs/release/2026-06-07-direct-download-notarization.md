# 2026-06-07 Direct Download Notarization

**Status:** notarized, stapled, uploaded, and live-site verified  
**Current canonical website:** `https://momentum-future.vercel.app`  
**App bundle:** `dist/CamiFitApp.app`  
**Final zip:** `dist/releases/Momentum-macOS-20260607-4.zip`  
**Notary zip:** `dist/releases/notary-Momentum-macOS-20260607-4.zip`

## Signing Identity

```text
Developer ID Application: Jake Kinchen (BN58T9KR6C)
Certificate ID: LSTJ33D4S3
Certificate SHA-1: DAD471316C2A62BBCB17BA6D8DCA7B8E5DFE1BC5
Certificate SHA-256: C47B97805000AA2CD42507F3138451A90AC329C49001C66FE309C8ECB74593AF
Issuer: Developer ID Certification Authority, G2
Expiration: 2031/06/08
```

The certificate was generated from the local CSR at:

```text
dist/signing/jake-developer-id-application.csr
```

## Notary Evidence

```text
Profile: CamiFitNotary
Submission ID: 92722e7e-6197-44ce-aef7-78b764001cfc
Submitted artifact: notary-Momentum-macOS-20260607-4.zip
Status: Accepted
Secure timestamp: 2026-06-07 22:52:54 +0000
```

## Final Artifact

```text
SHA-256  dist/releases/Momentum-macOS-20260607-4.zip
7705bbe3d757940d8e5ba2c7a9fdb5dd9f1704b4c40303419175d2c8e4a22d3b
Size: 42,278,225 bytes
```

The final zip was extracted and the app inside was verified with:

```bash
codesign --verify --deep --strict --verbose=2 CamiFitApp.app
xcrun stapler validate -v CamiFitApp.app
spctl -a -vv CamiFitApp.app
```

Expected and observed Gatekeeper result:

```text
CamiFitApp.app: accepted
source=Notarized Developer ID
origin=Developer ID Application: Jake Kinchen (BN58T9KR6C)
```

## Supabase And Website Evidence

```text
Supabase project ref: uyqdfbyggguxlwnghedt
Bucket: momentum-releases
Stable object: Momentum-macOS.zip
Versioned object: Momentum-macOS-20260607-4.zip
Public URL: https://uyqdfbyggguxlwnghedt.supabase.co/storage/v1/object/public/momentum-releases/Momentum-macOS.zip?download=Momentum-macOS.zip
Historical website URL: https://website-rho-one-42.vercel.app
Historical download route: https://website-rho-one-42.vercel.app/download
```

Observed live-site Mac download headers:

```text
HTTP/2 307
location: https://uyqdfbyggguxlwnghedt.supabase.co/storage/v1/object/public/momentum-releases/Momentum-macOS.zip?download=Momentum-macOS.zip

HTTP/2 200
content-type: application/zip
content-length: 42278225
last-modified: Sun, 07 Jun 2026 22:54:26 GMT
```

The zip downloaded through the historical
`https://website-rho-one-42.vercel.app/download` route
matched the local notarized artifact byte-for-byte:

```text
7705bbe3d757940d8e5ba2c7a9fdb5dd9f1704b4c40303419175d2c8e4a22d3b  /tmp/Momentum-from-site-20260607-4.zip
downloaded-zip-matches-local
```

iPhone user-agent requests to `/download` rendered the Mac handoff page and did
not expose the Supabase zip URL.

## Downloaded App Smoke

The live-site zip was extracted to `/tmp/camifit-site-download.6xtsU6` and the
downloaded app passed:

```bash
codesign --verify --deep --strict --verbose=2 CamiFitApp.app
xcrun stapler validate -v CamiFitApp.app
spctl -a -vv CamiFitApp.app
```

The extracted app contains no `Contents/Resources/CamiFitRepoRoot.txt`. Its
bundled pose worker health check returned `pose_ready:true`.

Launching the downloaded app and pressing Live Camera spawned the bundled helper
from the downloaded app path:

```text
/tmp/camifit-site-download.6xtsU6/CamiFitApp.app/Contents/Resources/camifit-pose-worker/camifit-pose-worker --mode mediapipe --model /private/tmp/camifit-site-download.6xtsU6/CamiFitApp.app/Contents/Resources/pose_worker/models/pose_landmarker_lite.task
```

After allowing the macOS camera permission prompt for the diagnostic launch,
`CAMIFIT_FRAME_DIR=/tmp/camifit-frame-proof` captured 115 `live_*.jpg` frames
from the downloaded app's Live Camera path. The visible app preview showed the
camera feed with `Stop`, `Skeleton`, and `Record` controls active.
