# July 1 (evening) Direct Download DMG — Authored Batch, Lane Merge, Rig Fix

**Release:** `macos-20260701-2`
**Final DMG:** `dist/releases/Momentum-macOS-20260701-2.dmg`
**Stable GitHub asset:** `Momentum-macOS.dmg`
**SHA-256:** `2f1a840665e3f514cdeb03754e10266c515700da3fb86c1e7c53c76403e2a05f`

GitHub release: https://github.com/jakekinchen/momentum/releases/tag/macos-20260701-2
Live site download: https://momentum-future.vercel.app/download (redirects to
the stable latest asset; verified serving this build via
`release_health_check.sh`).

## What shipped

1. **Guide inventory: 5 → 8.** The authored keypose lane adds
   `resistance_band_reverse_curl`, `single_arm_dumbbell_preacher_curl`, and
   `wide_grip_preacher_curl_with_ez_bar` — wrist keyposes generated from
   exact elbow-angle rotations about the pinned elbow (175° → 66–68° → 175°),
   preset form rules validated by construction (`AuthoredCurlFormTests`).
   Measured accuracy: bone-length CV 0.012, zero form-violation frames. The
   June visual-review demotions of the preacher-curl extractions are
   superseded; planner/coach/catalog now treat these as guided.
2. **Horizontal-pose rig fix.** Stance-foot centering pushed horizontal
   bodies off-camera (shipped pushup nose rendered at scene x=2.44 vs ~1.0
   visible half-width) and the hidden mid-torso left ribcage and pelvis
   disconnected. The normalization context now falls back to bounding-box
   centering with a width-aware scale clamp, and a spine capsule bridges
   shoulder girdle to pelvis. `AvatarRigHorizontalPoseTests` pins the June
   failure modes as geometry invariants and doubles as the app-identical
   snapshot renderer (`CAMIFIT_RIG_SNAPSHOT_DIR`). Plank and pike are no
   longer rig-blocked; their promotion is now purely a data/review decision.
3. **Motion-review lane merged.** `origin/main`'s parallel factory lane
   (review-only gallery demos for every remaining exercise, capture-intake
   tooling and schemas, plank self-capture registration, gallery snapshot)
   merged with the authored lane. Review-only packaging
   (`packaging_scope=motion_review_gallery_demo_only`) is now first-class in
   the audits: allowed to ship for pending profiles, never promotable,
   integrity still enforced; stale integrity records across all ten
   review-only manifests were refreshed.

## Version control

- Local and `origin/main` histories reconciled by merge (17 remote commits ×
  9 local commits); `main` pushed to origin and mirrored (with tags) to
  gitlab. Release tags remain the exact-source anchors.
- The stale local machine-row experiment (test repoint to dist/) was
  superseded by the remote lane's committed fixture; preserved in stash
  `wip-machine-row-repoint-and-gitignore` rather than committed.

## CI / hygiene changes

- CI now runs `scripts/run_monorepo_gates.sh` as the single bar; the motion
  audit auto-selects its non-strict tier on fresh clones (no dist/
  source-chain artifacts) and the strict tier locally.
- The gates auto-discover every `scripts/motion_reference/test_*.py` suite.
- New packaging-gate consistency audit: `script/build_and_run.sh` loops must
  mirror `AppExerciseTrackingGate` (this failed a release at notarization
  time once; now it fails in seconds).
- `release_direct_download.sh` runs the full gates as preflight
  (`MOMENTUM_SKIP_PREFLIGHT_GATES=1` to skip). The preflight caught a stale
  normalizer integrity pin during this very release.
- Coach-thread reset test deflaked (state sampled in a transition window).

## Verification

- Full monorepo gates green (kg pytest, validation, artifact diff,
  conformance, full Swift suite 402+ tests, all motion suites, strict audit
  failures=0).
- Installed-app inventory: exactly 8 guide-playable JSONLs (review-only
  gallery demos excluded from the guide count) at
  `/Applications/Momentum.app`; stapler validate passed.
- `release_health_check.sh`: app bundle, local DMG, and live stable download
  all validated with the SHA above.
