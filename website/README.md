# Momentum Website

Self-contained Next.js App Router marketing site for Momentum, positioned as
your future coach for local Mac training.

## Run Locally

```bash
cd website
npm install
npm run dev
```

Open `http://localhost:3000`.

Production is published at:

```text
https://momentum-future.vercel.app
```

## Build

```bash
cd website
npm install
npm run build
```

To expose the public Mac download CTA, set this server-side environment
variable before the production build:

```bash
MOMENTUM_DOWNLOAD_URL="https://github.com/jakekinchen/momentum/releases/latest/download/Momentum-macOS.dmg"
```

The site routes all CTA clicks through `/download`. Desktop Mac browsers are
redirected to the DMG; iPhone, iPad, Android, and other non-Mac browsers are
sent to `/download/mac`, which also includes a direct DMG link for manual
download or copy/share flows.

## Release Download Storage

The production `/download` route currently points at GitHub Releases:

```text
https://github.com/jakekinchen/momentum/releases/latest/download/Momentum-macOS.dmg
```

This is the large-file workaround for Supabase Storage's Free-plan object limit.
Supabase can still be used as a mirror for small artifacts, but bundled builds that
include large native helpers such as Codex should publish through GitHub
Releases instead of Supabase.

After `scripts/release_direct_download.sh` creates, signs, notarizes, staples,
and smoke-tests the drag-to-Applications DMG, publish the public download asset
with:

```bash
MOMENTUM_RELEASE_VERSION=20260608-4 \
MOMENTUM_UPDATE_VERCEL_DOWNLOAD_URL=1 \
MOMENTUM_DEPLOY_WEBSITE=1 \
  scripts/publish_github_release_download.sh
```

The script uploads both `Momentum-macOS.dmg` and the versioned DMG name to the
GitHub release, verifies the stable URL's SHA-256 against the local artifact,
and optionally updates/redeploys the Vercel production download route.

## App Asset Provenance

- `public/app-assets/brand/future.svg` is copied from the macOS app brand resources.
- `public/app-assets/onboarding/movement-tracking-swiftui.*` is rendered from the SwiftUI `OnboardingFeatureVisual(stepID: .movement)` source through `website/experiments/onboarding-video/capture-swiftui-onboarding.sh`.
- `public/app-assets/product/momentum-app-workout-hero.{webm,mp4,jpg}` is a moving marketing composite: the local Mac app QA screenshot from `dist/qa-screenshots/2026-06-06-01-baseline.png` with the 30-36s segment from `dist/motion-reference/bodyweight_lunge/source/commons-forward-lunge.webm` placed inside the live camera surface and overlaid with the matching `raw_mediapipe.jsonl` skeleton trace. The renderer applies a 5-frame median despike plus a centered 5-frame Savitzky-Golay smoothing pass to reduce pose shimmer while keeping the rig source-aligned, then adds a timed `REPS` badge that increments from 2 to 3 with a green `+1 REP` pulse at the bottom of the lunge. Regenerate it with `node website/experiments/hero-video/render-moving-workout-hero.mjs`.
