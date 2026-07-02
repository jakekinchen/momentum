# 2026-06-06 Conformance Release Closeout

**Status:** validated local release candidate  
**Branch:** `feat/monorepo-synthesis`  
**App bundle:** `dist/CamiFitApp.app`  
**Zip artifact:** `dist/CamiFitApp-release-20260606.zip`

## Current Artifact

The current zip was rebuilt after correcting the signing path so the bundle is
not signed with Austen's account.

```text
SHA-256  dist/CamiFitApp-release-20260606.zip
1182881cee1527f9d0dced66faaad6ec588d207dfc44cdc03dccc6f89b231d65
```

Current extracted app signature:

```text
Authority=Apple Development: Jake Kinchen (SYXDY3MK8F)
Authority=Apple Worldwide Developer Relations Certification Authority
Authority=Apple Root CA
TeamIdentifier=BN58T9KR6C
```

Release-configuration direct-download signing now requires a Jake
`Developer ID Application` certificate and fails closed if that identity is not
installed. The earlier `Apple Distribution: Jake Kinchen (BN58T9KR6C)` path is
not the correct public website download path.

```bash
./script/build_and_run.sh release
```

The June 7 direct-download release created the Jake Developer ID Application
certificate and stored a validated `CamiFitNotary` profile. See
`docs/release/2026-06-07-direct-download-notarization.md`.

Older development-signed zips are expected to fail Gatekeeper assessment:

```text
spctl --assess --type execute --verbose=4 dist/CamiFitApp.app
dist/CamiFitApp.app: rejected
```

## App Configuration

- Product executable: `CamiFitApp`
- Display name: `Future Coach`
- Bundle identifier: `com.camifit.app`
- Minimum macOS version: `26.0`
- Package script: `script/build_and_run.sh`
- Legacy/divergent script: `scripts/build_camifit_app.sh`
  - This older script stages `dist/CamiFit.app`, display name `CamiFit`, and an
    executable named `CamiFit`.
  - Use `script/build_and_run.sh` for the current release path.

## GUI QA Evidence

Screenshots captured under `dist/qa-screenshots/`:

| Screenshot | Evidence |
|---|---|
| `2026-06-06-01-baseline.png` | Baseline app shell after onboarding bypass. |
| `2026-06-06-02-workout-receipt.png` | Found plank target mismatch before fix. |
| `2026-06-06-03-workout-receipt-fixed.png` | Fixed plan card shows `Bodyweight Plank`, `3 sets x 30s hold`, no validation error. |
| `2026-06-06-04-copilot-sleep.png` | `Sleep this week` routes to graph-backed Copilot fact card with chart and evidence node. |
| `2026-06-06-05-workout-added.png` | `Add Routine` changes to `Added`; `KG 50-Minute Workout` appears in routines. |
| `2026-06-06-06-release-launch.png` | Release bundle launches and shows the expected app surface. |

## Validated Product Behavior

- Workout requests route through `AssignmentWorkoutPlanner` and KGKit before
  app routine conversion.
- Timed-hold exercises such as `bodyweight_plank` compile as hold targets, not
  rep targets.
- KG workout cards show selected exercises, filtered exercises, graph paths,
  reason codes, alternatives, and app preset mapping status.
- Copilot fact cards cover sleep, adherence, changed-since-last-week, message
  pattern, churn risk, brief, and no-supporting-fact behavior.
- `Add Routine` attaches the graph-derived workout to the app routine list.
- Packaged resources include app presets, motion demos, avatar resources, and
  KG assignment artifacts.

## Verification Commands

Focused checks run during closeout:

```bash
swift test --disable-sandbox --filter AssignmentWorkoutPlannerTests
swift test --disable-sandbox --filter RoutineCompilerTests
./script/build_and_run.sh --verify
./script/build_and_run.sh release
codesign --verify --deep --strict --verbose=2 dist/CamiFitApp.app
git diff --check
```

Full gates:

```bash
swift test --disable-sandbox
scripts/run_monorepo_gates.sh
```

The full gate covers Python KG tests, graph validation, assessment import,
generated-artifact idempotence, Swift conformance parity, full Swift tests,
motion coverage, KG motion readiness, and current contracts listing.

## Direct Download Follow-Up

The June 7 direct-download path is now published through Supabase and the
website. The shipped artifact is `dist/releases/Momentum-macOS-20260607-4.zip`
with SHA-256
`7705bbe3d757940d8e5ba2c7a9fdb5dd9f1704b4c40303419175d2c8e4a22d3b`.

The current canonical website is `https://momentum-future.vercel.app`. At this
historical checkpoint, the route
`https://website-rho-one-42.vercel.app/download` redirected Mac desktop
browsers to the stable Supabase object and sent iPhone/non-Mac browsers to the
Mac handoff page. The zip downloaded through the live site was extracted,
Gatekeeper-validated, and launched. Live Camera spawned the bundled
`Contents/Resources/camifit-pose-worker/camifit-pose-worker` helper from the
downloaded app bundle rather than the local repo venv.

## Residual Release Limits

- The app is a direct-download Developer ID release, not an App Store/TestFlight
  upload.
- Camera preview still depends on the user's local webcam/privacy state, but
  the packaged pose worker no longer depends on a local MediaPipe venv.
- The KG assignment data remains synthetic and assessment-scoped.
