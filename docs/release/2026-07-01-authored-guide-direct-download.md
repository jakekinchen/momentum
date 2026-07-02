# July 1 Direct Download DMG — First Authored Guide

**Release:** `macos-20260701-1`
**App bundle:** `dist/Momentum.app`
**Final DMG:** `dist/releases/Momentum-macOS-20260701-1.dmg`
**Stable GitHub asset:** `Momentum-macOS.dmg`

## Summary

Ships the fifth guide-ready exercise, `standing_miniband_hip_flexion`, produced
by the new zero-budget authored keypose lane (no first-party recording, no
external motion data): constant-bone-length keyposes sampled through a
circular Catmull-Rom timeline in
`scripts/motion_reference/compile_archetype_trace.py`, validated by
form-by-construction unit tests that mirror the preset's own rep/form rules.

Guide inventory is now: `bodyweight_lunge`, `bodyweight_pushup`,
`bodyweight_squat`, `single_arm_cable_tricep_extension`,
`standing_miniband_hip_flexion`.

Strategy background: `docs/research/2026-07-01-no-first-party-motion-sourcing.md`.

## Artifacts

```text
f96c2aaf1a975ad582de74b2e6ec6c84a7d0add451f8b61ea32d89fb1855b51c  dist/releases/Momentum-macOS-20260701-1.dmg
b5dfcff284974efbfd367a9bcb0aef981865eca911493900cca42e187184834f  dist/releases/Momentum-macOS-20260701-1.zip
```

GitHub release: https://github.com/jakekinchen/momentum/releases/tag/macos-20260701-1
Stable download: https://github.com/jakekinchen/momentum/releases/latest/download/Momentum-macOS.dmg
Live site download: https://momentum-future.vercel.app/download

The release tag `macos-20260701-1` was pushed directly (local `main` and
`origin/main` have diverged; reconciling branches was deliberately left out of
this release — the tag carries the exact source used for the build).

## Verification

- Full Swift suite: 402 tests, 0 failures (includes the new
  `standing_miniband_hip_flexion` engine-replay case: 35 frames, 1 rep
  counted, stance contacts pinned, loop closure exact).
- Motion gates: gap report `guide_ready=5 provenance_complete=5`;
  `audit_motion_coverage.py --strict --require-trackable-reference-clips
  --require-guide-ready-inventory` failures=0; accuracy baseline updated with
  measured authored-trace ceilings (bone CV 0.015 measured vs 0.05 ceiling).
- Installed-app review: `dist/Momentum.app` installed to
  `/Applications/Momentum.app`; installed inventory contains exactly five
  playable JSONL traces including `standing_miniband_hip_flexion`; stapler
  validate passed.
- Release health check against the stable URL:

```text
ok: validated app bundle (Notarized Developer ID, accepted)
ok: validated DMG dist/releases/Momentum-macOS-20260701-1.dmg
ok: validated live download https://github.com/jakekinchen/momentum/releases/latest/download/Momentum-macOS.dmg
```

- Live site redirect check: `GET /download` (mac desktop UA) → HTTP 307 →
  `releases/latest/download/Momentum-macOS.dmg` (now serving this build; no
  site redeploy required).

## Tooling change: headless DMG layout

Finder AppleScript layout timed out in this (headless) release context
(`AppleEvent timed out (-1712)`), so `scripts/release_direct_download.sh` now
supports a `.DS_Store` layout template: when
`scripts/release_assets/momentum_dmg_layout.DS_Store` (harvested from the
shipped `macos-20260619-1` DMG, identical item names and background filename)
is present — or `MOMENTUM_DMG_LAYOUT_DS_STORE` points at one — the Finder
automation pass is skipped and the DMG is created directly with the template
layout. Interactive Finder layout remains the fallback when no template
exists.

## Gate changes in this release

- `script/build_and_run.sh`: `standing_miniband_hip_flexion` moved from the
  blocked-resource loop to the required-packaged loop.
- `AppExerciseTrackingGate.guideReadyPresetIDs` gained the exercise;
  `referenceCaptureRequiredPresetIDs` dropped it.
- `MotionDemoSourceKind` gained `canonical_archetype_authored`;
  `MotionDemoManifest.isGuideEligible` accepts the authored kind (source
  video/raw trace requirements now apply only to capture-derived kinds, and
  candidate `canonical_archetype_trace` manifests remain fail-closed).
- `exercise_motion_profiles.json` reference policy accepts first-party
  authored canonical keypose timelines; the profile exited fail-closed with
  `capture.status=first_party_authored_keyposes`,
  `viewer_status=bundled_canonical_trace`.
