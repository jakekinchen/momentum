# Bodyweight Lunge Reference Pipeline

**Date:** 2026-06-06  
**Status:** Golden-reference guardrail for the lunge motion trace
**Scope:** Preserve the ideal Bodyweight Lunge avatar guide and use it to
validate future extraction candidates.

## Decision

For Bodyweight Lunge, the ideal source is a first-party trainer reference video
processed through the same MediaPipe pose boundary used by tracking. Public
datasets are useful as validation and sanity checks, but they should not become
the primary product demo source unless licensing, view, exercise variant, and
retargeting quality are all reviewed.

The current bundled trace is the protected canonical guide. Do not overwrite
`Sources/CamiFitApp/Resources/MotionDemos/bodyweight_lunge.jsonl` or its
manifest with raw-preserved extraction output by default. External or
first-party lunge clips should be kept under `dist/motion-reference/` and
compared against the protected guide before any explicit product decision to
replace it.

## Why the Current Lunge Was Wrong

The earlier procedural lunge failed in two ways:

- it allowed foot landmarks to move when the viewer should preserve planted
  contact constraints;
- it authored support-leg knee/ankle points without a complete
  `secondary.shoulder`/`secondary.hip`/`secondary.knee`/`secondary.ankle` side,
  so the SceneKit rig could fail to render the intended support leg.

The current fallback now emits explicit `secondary.*` support-side landmarks and
keeps the contact landmarks stable. That only makes the fallback acceptable for
visual iteration. It does not make it authoritative motion data.

## Pipeline

1. Record a stationary side-view split lunge reference.
2. Run `scripts/motion_reference/export_mediapipe_reference_trace.py` to extract
   frames and call the existing `pose_worker` in MediaPipe `VIDEO` mode.
3. Run `scripts/motion_reference/normalize_lunge_trace.py` to:
   - choose the front leg as `primary.*`;
   - choose the rear/support leg as `secondary.*`;
   - copy raw `left.*` and `right.*` landmarks for engine parity;
   - smooth non-contact landmarks;
   - pin front/support foot contact landmarks.
4. Keep the reviewed candidate under `dist/motion-reference/` and compare it
   against the protected guide:
   `scripts/motion_reference/compare_trace_to_golden.py --golden Sources/CamiFitApp/Resources/MotionDemos/bodyweight_lunge.jsonl --candidate <candidate.jsonl> --output <comparison.json>`.
5. If a human explicitly approves replacing the protected guide, regenerate with
   `--allow-promote-bodyweight-lunge` so the manifest records a promotion
   command instead of the default comparison command.
6. Launch with
   `CAMIFIT_GUIDE_EXERCISE=bodyweight_lunge ./script/build_and_run.sh --verify`
   and inspect the guide before accepting any replacement.

## Dataset Role

- MM-Fit is the best public bootstrap check because it includes workout
  exercises, RGB-D video, and 2D/3D pose estimates, including lunges.
- Fit3D is the stronger 3D/retargeting reference because it includes repeated
  fitness exercises with accurate 3D skeletons plus GHUM and SMPL-X parameters.
- UI-PRMD is useful for an inline-lunge sanity check, but it is rehabilitation
  data and may not match the product's bodyweight-lunge variant or camera view.

## Viewer Acceptance

For this first lunge, the viewer should read as:

- stationary split-stance lunge, not alternating lunges;
- front foot flat and planted;
- rear/support foot planted enough that the avatar does not slide;
- front knee bends forward and downward without inversion;
- support knee bends naturally toward the floor;
- torso remains tall;
- one rep still passes through the engine when replayed.
