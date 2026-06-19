# Guide Motion Accuracy Harness

**Date:** 2026-06-09
**Status:** Implemented
**Scope:** Quantify how accurate every exercise guide motion path is, using the
protected bodyweight lunge trace as the golden calibration and regression
anchor, so inaccurate guides are detected automatically instead of by eye.

## Problem

Guide accuracy today is checked by hand-written, per-exercise assertions in
`MotionDemoTimelineTests` plus a one-off Python comparison for the lunge. The
checks are uneven: the lunge has ~10 biomechanical assertions, most exercises
have 3, and nothing measures whether a guide skeleton is even anatomically
possible. The procedural squat, for example, animates the ankle upward while
hip and knee stay fixed, so the shin and thigh change length every frame —
"mostly looks fine" in the viewer but is exactly the class of bug that shipped
the original lunge contact violation.

There is no single number that answers "how accurate is this guide?" and no
gate that fails when a guide gets worse.

## Approaches considered

1. **Extend the Python tooling** (`scripts/motion_reference/`). Rejected as the
   core: 10 of 14 guides are procedural and only exist after
   `MotionDemoCompiler.compile()` runs in Swift; Python would also have to
   re-implement preset signals, rep predicates, and form rules.
2. **Swift scorer inside CamiFitEngine, driven by tests.** Scores any
   `MotionDemoTimeline` — recorded JSONL or procedural — using the same engine
   that measures real users. Chosen as the core.
3. **Hybrid.** Option 2 plus keep `compare_trace_to_golden.py` and the manifest
   gates for source-video fidelity of recorded traces. Chosen overall; the
   Python layer already works and covers a dimension (fidelity to the source
   clip) that the Swift layer cannot.

## Accuracy model

A guide is accurate when all four layers hold. Layers 1–3 are computed by the
new Swift scorer for every exercise; layer 4 stays in the existing Python/
manifest pipeline for recorded traces.

1. **Skeleton integrity.** For every bone segment whose endpoints exist in all
   frames (shoulder–hip, hip–knee, knee–ankle, shoulder–elbow, elbow–wrist per
   `primary`/`secondary`/`left`/`right` family), the segment length's
   coefficient of variation across frames, reported as the worst segment.
   Measurement showed this is a *projection* metric, not an absolute accuracy
   gate: real side-view recordings foreshorten limbs that rotate out of the
   image plane (the golden lunge's rear shank varies 33%), while flat
   procedural rigs can hold lengths nearly constant. It is therefore pinned
   per exercise as a regression metric rather than compared across guides.
2. **Exemplar semantics.** Replay the timeline through `EngineTraceRecorder`
   with the exercise's own preset:
   - rep exercises count exactly one rep per loop;
   - observed phase-signal range covers the preset `min_rom_deg`;
   - zero frames where any form rule is active with a failed expectation. The
     guide is the exemplar — if the guide itself earns "Lower into the lunge,"
     the motion path is wrong by the product's own definition.
   - hold exercises (plank) instead replay enough loops to span the hold target
     and must reach a completed hold with no form violations.
3. **Motion quality.**
   - peak landmark speed in body-scale units/second (catches teleporting
     joints between keyframes);
   - loop-closure gap between first and last frame in body-scale units
     (catches the visible snap when the guide loops);
   - median noise-to-signal ratio (per-frame acceleration ÷ velocity over all
     common landmarks; added 2026-06-10). Above ~1, estimation noise exceeds
     true per-frame motion and the guide visibly trembles — this is the metric
     that catches "the guide feels jittery", which peak speed and bone CV both
     missed. The raw lunge golden measured 1.11; recorded traces are now
     keyframe-smoothed at timeline construction (`MotionDemoKeyframeSmoother`,
     two zero-lag binomial passes, golden JSONL untouched, anchors and loop
     frames provably preserved), bringing played-back lunge noise to ~0.30.
     The scorer evaluates recorded guides post-smoothing — what the app plays.
     Note: three passes was measurably too much (the cable tricep guide
     stopped counting a rep), which is why the pass count is pinned by the
     harness rather than tuned by eye.
4. **Source fidelity (recorded traces only, existing).**
   `compare_trace_to_golden.py` body-scaled landmark error + angle correlation
   against the raw source trace, plus manifest `artifact_integrity` hashes.

All geometry uses 2D `x`/`y` only. Presets are `image2d`; `z` is synthetic in
procedural rigs and is the least reliable MediaPipe channel. Body scale is the
median over frames of the hip→ankle distance (same convention as
`compare_trace_to_golden.py`), so metrics are invariant to subject size and
framing.

## The lunge as golden test

The shipped `bodyweight_lunge.jsonl` (acceptance status
`protected_golden_loop_closed`) plays two roles:

1. **Regression pin.** `testGoldenLungeRecordedTraceAccuracyStaysPinned`
   computes the full report for the recorded lunge trace and asserts every
   metric inside a tight pinned band. Any change to the trace, decoder, or
   scorer that moves lunge accuracy fails loudly. Pinned values from the
   2026-06-09 measurement: 108 frames, 1 rep, 78.5° observed ROM, bone-length
   CV 0.326 (worst segment `secondary.knee→secondary.ankle`, real
   foreshortening of the occluded rear shank), peak landmark speed 0.77
   body-lengths/s, loop gap 0, and 31 frames violating the `depth` form rule
   (see Findings).
2. **Calibration reference.** The lunge's measured values anchor what "a
   known-good recorded guide" looks like on every metric — e.g. recorded
   human motion peaks below ~1 body-length/s while the procedural rigs reach
   2.4–4.4, and a clean loop has gap 0. Per-exercise ceilings in the baseline
   were taken from each guide's own measurement with small headroom, so the
   fleet can only move toward the lunge's quality, never away from it.

## Findings from the first measurement

- **Every guide except the plank violates at least one of its own form
  rules** when replayed through the engine. The golden lunge itself fails its
  `depth` rule on 31 of 108 frames: the rule expects `front_knee <= 100` at
  the bottom, but the trace's raw minimum knee angle is 100.07° (manifest
  `summary.min_primary_knee_angle`), higher still after the preset's EMA
  filter. Either the depth thresholds are stricter than the approved
  reference motion or the guides are genuinely shallow — both are accuracy
  bugs by the product's own definition, now visible per exercise in the
  scorecard (`depth`, `curl_height`, `pike_depth`, `extension_finish`,
  `press_finish`, `row_finish`, `elbow_path`, `knee_drive`, …).
- **Procedural rigs move limbs 3–6× faster than recorded human motion**
  (peak 2.4–4.4 vs 0.5–0.9 body-lengths/s) — a measurable signature of why
  they read as robotic.
- All 14 guides count exactly one rep (plank reaches its hold target), cover
  the preset minimum ROM, and loop with zero closure gap.

## Components

- `Sources/CamiFitEngine/MotionGuideAccuracy.swift`
  - `MotionGuideAccuracyScorer.score(program:frames:sourceKind:)` →
    `MotionGuideAccuracyReport` (Codable). Pure function over pose frames; no
    file or bundle access, so it can score recorded JSONL, procedural compiles,
    or future captures identically.
  - `MotionGuideAccuracyThresholds.failureReasons(for:)` — turns a report plus
    per-exercise ceilings into human-readable regression reasons, and always
    enforces the absolute invariants (1 rep or hold reached, ROM ≥ preset
    minimum).
- `Tests/CamiFitEngineTests/MotionGuideAccuracyTests.swift`
  - golden lunge pin test (recorded trace);
  - a fleet test that scores the guide **the app actually ships** for all 14
    presets (recorded JSONL when packaged and playable, else the procedural
    compile), prints one scorecard line per exercise, writes
    `dist/motion-accuracy/scorecard.json`, and enforces the baseline ratchet.
- `Tests/CamiFitEngineTests/Fixtures/motion_accuracy_baseline.json`
  - committed per-exercise ceilings (source kind, bone-length CV, peak speed,
    loop gap, form-violation frames) captured from the current measurement.
    The fleet test fails when any exercise regresses past its ceiling or a
    recorded trace is silently demoted to procedural; improving a guide passes,
    and its ceilings should then be tightened to lock in the gain. The stated
    goal state is `max_form_violation_frames: 0` everywhere.

## What this buys

- "Which guides are inaccurate?" becomes `swift test --filter
  MotionGuideAccuracy` and reading the scorecard, instead of opening the
  viewer 14 times.
- Fixing a procedural rig (or replacing it with a recorded trace) has a
  numeric definition of done: classification flips to `accurate` and the
  baseline tightens.
- The lunge can never silently degrade; everything else can never silently get
  worse than it is today.

## Out of scope

- Scoring visual retargeting onto the 3D mannequin (SceneKit rig); the scorer
  stops at `PoseFrame` landmarks, which is what the rig consumes.
- Replacing the per-exercise biomechanical tests; they assert
  exercise-specific shape (e.g. rear-heel lift) that a generic metric cannot.
- Generating new reference captures; see
  `2026-06-06-scalable-motion-reference-pipeline.md`.
