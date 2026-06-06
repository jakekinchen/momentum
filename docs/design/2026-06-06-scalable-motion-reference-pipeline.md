# Scalable Motion Reference Pipeline

**Date:** 2026-06-06
**Status:** Initial implementation scaffold
**Scope:** Make avatar guide motion scalable across every exercise the app can
measure.

## Decision

The scalable path is not to hand-author every exercise in Swift. The product
source of truth should be a small first-party library of controlled trainer
reference videos, one exercise variant at a time, processed through the same
MediaPipe boundary used for tracking and then compiled into app-ready
`PoseFrame` JSONL.

Public fitness-motion datasets can help bootstrap and validate archetypes, but
they should not be the primary shipped demo source until licensing, exercise
variant, camera view, skeleton format, and visual retargeting have all been
reviewed. The first-party capture path gives us variant control, consistent
camera assumptions, and a reviewable source clip for every packaged trace.

## Compiler Contract

Each exercise needs a motion profile before it gets bundled demo data:

- exercise id from the packaged preset;
- archetype, such as split lunge, squat, horizontal press, or static hold;
- capture instructions and contact policy;
- phase driver and top/bottom or hold semantics;
- normalizer or retarget mode;
- required contact landmarks;
- required output landmarks;
- automated QA gates.

The profile registry lives at
`scripts/motion_reference/exercise_motion_profiles.json`. The app consumes only
compiled JSONL under `Sources/CamiFitApp/Resources/MotionDemos`; scripts and
profiles own capture, phase, smoothing, contact anchoring, and visual retargeting.

## Standard Pipeline

```text
exercise preset
  -> motion profile
  -> trainer reference clip
  -> MediaPipe VIDEO trace
  -> archetype normalizer
  -> contact and phase QA
  -> app MotionDemos JSONL
  -> engine replay test and viewer review
```

Raw MediaPipe landmarks are useful for extraction and debugging. They are not
enough for the avatar viewer by themselves because they do not encode product
semantics like `primary.knee`, planted-foot policy, loop boundaries, or stable
side-view retargeting.

## Current Coverage

- `bodyweight_lunge`: bundled interim reference trace, normalized through
  `normalize_lunge_trace.py`, with a canonical stationary-lunge display retarget.
- `bodyweight_squat`: bundled canonical archetype trace exists; still needs
  first-party reference capture to replace the deterministic interim trace.
- `bodyweight_pushup`: preset and engine tests exist; needs first-party
  reference capture to replace the bundled horizontal-press archetype trace.
- `bodyweight_plank`: bundled canonical hold trace exists; still needs
  first-party hold capture to replace the deterministic interim trace.

Run the audit:

```bash
scripts/motion_reference/audit_motion_coverage.py --strict
```

Use `--require-all-demos` when we are ready to fail CI until every packaged
exercise has a valid bundled demo.

## Acceptance Gates

Every shipped motion demo should pass:

- profile exists for the preset exercise id;
- required landmarks are present in the compiled JSONL;
- declared contact landmarks remain locked or within a profile-specific
  tolerance;
- first and last loop frames match closely enough to avoid visible jitter;
- rep or hold replay succeeds through the same engine preset;
- visual review confirms the movement reads as the intended exercise.

The lunge bug is the reason for these gates. The viewer was "mostly good" while
still violating exercise contact and support-leg expectations. Scalable quality
requires those assumptions to be explicit before the avatar ever renders.

## Next Implementation Slice

Build a generic `normalize_reference_trace.py` around archetypes, then move the
lunge-specific pieces into the split-lunge archetype:

- `split_stance_lunge`;
- `bilateral_squat` currently has a canonical trace compiler;
- `horizontal_press` currently has a canonical trace compiler;
- `static_hold` currently has a canonical trace compiler.

Each archetype should output the same `motion_demo_pose` record shape and write
a manifest summarizing source clip, selected cycle, retarget mode, contacts, and
QA metrics. That lets future exercises become capture plus profile work instead
of frame-by-frame visual tuning.
