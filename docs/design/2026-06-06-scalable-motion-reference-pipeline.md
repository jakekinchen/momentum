# Scalable Motion Reference Pipeline

**Date:** 2026-06-06
**Status:** Active baseline with KG readiness audit
**Scope:** Make avatar guide motion scalable across every exercise the app can
measure, while keeping KG recommendation nodes separate from app-runnable
exercise presets.

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

- `bodyweight_squat`: packaged preset, motion profile, bundled trace, and
  manifest are present.
- `bodyweight_lunge`: packaged preset, motion profile, bundled stationary-lunge
  trace, and manifest are present.
- `bodyweight_pushup`: packaged preset, motion profile, bundled trace, and
  manifest are present.
- `bodyweight_plank`: packaged preset, motion profile, bundled canonical hold
  trace, and manifest are present.

Those four IDs are the current app-runnable exercise set. They can be selected
in the UI, displayed in the avatar guide, and measured by the engine.

The KG has a broader exercise vocabulary. The shipped KG artifact currently has
seven `Exercise:*` nodes used for safety, alternatives, and workout generation.
The generated candidate-assessment KG imports the 50 assignment exercise
records. Those graph exercises are recommendation data unless they map to a
packaged app preset with a motion profile and bundled demo trace. Do not treat a
KG node as displayable or measurable just because it appears in the graph.

Run the audit:

```bash
scripts/motion_reference/audit_motion_coverage.py --strict
scripts/motion_reference/audit_kg_motion_readiness.py --summary-only
```

Use `--require-all-demos` when we are ready to fail CI until every packaged
exercise has a valid bundled demo. Use `--require-all-kg-viewer-ready` only
when the product milestone requires every KG exercise node to be converted into
an exact app preset plus motion demo.

## KG To App Readiness Contract

An exercise is guide/measurement-ready only if all of these are true:

- the app ships `Sources/CamiFitApp/Resources/Presets/<exercise_id>.json`;
- `scripts/motion_reference/exercise_motion_profiles.json` has a profile for
  that exact app exercise id;
- the app ships
  `Sources/CamiFitApp/Resources/MotionDemos/<exercise_id>.jsonl`;
- the demo has a matching manifest;
- the coverage audit accepts required landmarks, contacts, and loop closure;
- if the exercise came from KG, the KG node explicitly maps to that app preset
  through a future property such as `camifit_preset_id`.

Without that mapping, KG exercises stay recommend-only. Approximate archetype
reuse is allowed for internal prototyping, but it is not an exact exercise guide
and should not be surfaced as "show me how to do this exercise."

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
