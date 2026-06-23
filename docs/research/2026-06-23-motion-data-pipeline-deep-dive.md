# Motion Data Pipeline Deep Dive

Date: 2026-06-23

## Working Conclusion

The current pipeline is valuable, but it is still too close to:

```text
available video -> pose detector -> normalized JSONL -> app avatar
```

That can produce structurally valid files that still look wrong. The ideal
pipeline should split three different jobs that are currently easy to blur:

1. **Instructional avatar motion**: what the user sees as the ideal movement.
2. **Detector validation data**: what the runtime pose detector should see from
   real camera footage.
3. **Rep/form measurement data**: the signal thresholds and phase logic used by
   the app.

The best path is a small internal motion-data factory built around first-party
or explicitly licensed trainer captures, multi-view reconstruction where
possible, strict source provenance, and visual QA before promotion.

## Current Repo State

Generated with:

```bash
python3 scripts/motion_reference/report_motion_pipeline_gaps.py \
  --json-output tmp/motion-review-deep-dive/gap-report.json \
  --markdown-output tmp/motion-review-deep-dive/gap-report.md
```

Observed state:

- 15 exercise rows in the motion report.
- 14 packaged app presets.
- 4 playable JSONL traces.
- 4 app-gate guide-ready traces.
- 11 reference-capture-required traces.
- 4 blocked visual-review candidates.
- 4 guide-ready traces still rely on local-only `dist/` source-chain artifacts.
- KG generated graph has many recommendation-only or incomplete viewer rows.

The review gallery made the right failure mode obvious: a file can be
`playable_jsonl=true` while still being a bad product experience if the skeleton
motion is anatomically odd, source-unfaithful, or detached from detector truth.

## Why Some Motions Still Look Bad

### 1. Single-camera pose is not enough for final avatar motion

MediaPipe Pose Landmarker can output 2D image landmarks and 3D world landmarks,
and it supports video mode. That is useful extraction evidence, but it is still
model-estimated geometry from camera pixels, not a guaranteed clean motion
capture rig. The official task exposes thresholds for detection, presence, and
tracking confidence, which means low-confidence frames are expected and must be
gated, not smoothed into a final avatar trace.

### 2. Detector keypoints are not an exercise semantic model

Raw detector landmarks do not know "front knee," "support leg," "bench contact,"
"fixed foot," "loaded arm," or "machine handle path." Our normalizers add
semantic labels like `primary.knee`, which is the right direction, but promotion
needs a stronger exercise-specific contract before retargeting.

### 3. Visual plausibility is a separate acceptance gate

Some candidate traces can pass basic JSONL structure and still fail because the
rig bends badly, the limb identity flips, the movement phase is wrong, or the
loop boundary snaps. Those are product failures, not just data-format issues.

### 4. Web videos are a brittle source of truth

Public workout clips vary in camera angle, lens distortion, cropping, rep
tempo, clothing, occlusion, and license quality. They are useful candidates,
but not a dependable primary source for a polished movement library unless we
control the capture requirements and preserve source evidence.

## Source Options

### Best default: first-party trainer capture

Use our own trainer or trusted performer captures for most guide-ready motions.

Minimum viable capture setup:

- Tripod.
- Stable lighting.
- Full body visible including hands, feet, and equipment.
- 60 fps where possible.
- True side view for sagittal movements.
- Front or 45-degree view when symmetry matters.
- 2-3 clean reps at controlled tempo.
- Calibration frame: standing T/A-pose or known neutral stance.
- One source clip per exercise variation, not one clip reused across similar
  exercises.

Preferred setup:

- Two phones or cameras: side plus front/oblique.
- Shared clap/flash sync.
- Floor marker or known scale reference.
- Trainer metadata: height range, stance, equipment, camera distance, view,
  rep count, notes.

This gives us the cleanest path for both the avatar and detector validation.

### Strong upgrade: markerless multi-view 3D reconstruction

OpenCap-style approaches are relevant because they combine smartphone videos,
computer vision, and musculoskeletal simulation to estimate 3D movement
dynamics. OpenCap has published validation work for smartphone-based movement
analysis and is specifically closer to biomechanics than plain 2D keypoint
extraction.

For CamiFit, this should be treated as a motion-authoring aid, not necessarily
runtime dependency:

```text
two-phone trainer capture
  -> 2D keypoint extraction
  -> synchronized multi-view 3D reconstruction / IK
  -> canonical skeleton motion
  -> avatar retarget
  -> app JSONL plus source evidence
```

This is the path I would use for squats, lunges, hinges, planks, rows, and
anything where depth, contact, or equipment path matters.

### Useful but not sufficient: MediaPipe, MoveNet, RTMPose

These are detector/extraction tools, not the whole data pipeline.

- MediaPipe is already aligned with this repo because it outputs 33 landmarks,
  normalized image coordinates, and world coordinates, and is optimized for
  real-time fitness use.
- MoveNet is useful as a second-opinion detector: it is fast, has Lightning and
  Thunder variants, and is designed for real-time fitness/wellness use cases.
- RTMPose/MMPose is useful as a stronger research/offline extraction comparator
  when we want higher-confidence 2D keypoints and model-agreement scoring.

Recommended use:

```text
MediaPipe primary extraction
MoveNet/RTMPose agreement check
reject frames/clips with detector disagreement
never promote solely because one detector produced a complete skeleton
```

### Useful for priors, not direct product truth: AMASS and mocap datasets

AMASS is valuable because it unifies many optical marker-based mocap datasets
into a common SMPL/body-model representation. It can help with animation priors,
joint-limit constraints, and plausible human-motion regularization.

It is not enough by itself for this product because:

- many exercises will not match our exact preset definitions;
- licensing and commercial use must be checked per source dataset;
- it often lacks the exact camera/video evidence needed to validate the runtime
  detector experience;
- exercise equipment interactions are limited or inconsistent.

### Metadata only: wger and exercise catalogs

wger is useful as an open exercise catalog/API and reference metadata source,
but it is not a high-confidence source for polished avatar motion. Its exercise
content license is share-alike, so we should be careful about ingesting it into
product assets unless we are prepared for those license obligations.

## Recommended CamiFit Data Factory

### Stage 0: Exercise contract

For every preset, define:

- required camera view;
- primary/support limb rules;
- equipment contact points;
- required landmarks;
- phase driver;
- acceptable range of motion;
- contact invariants;
- measurement thresholds;
- visual acceptance checklist.

Output:

```text
Sources/CamiFitApp/Resources/Presets/<exercise_id>.json
scripts/motion_reference/exercise_motion_profiles.json
```

### Stage 1: Capture or source acquisition

Prefer first-party trainer capture. Use licensed external clips only when they
meet the capture contract.

Output:

```text
dist/motion-reference/<exercise_id>/<capture_id>/source_video.*
dist/motion-reference/<exercise_id>/<capture_id>/capture_session.json
```

`capture_session.json` should include:

- source kind;
- performer notes;
- camera view;
- fps/resolution;
- equipment;
- license/attribution;
- rejected alternatives;
- reviewer notes.

### Stage 2: Detector extraction with model agreement

Run multiple extractors offline:

- MediaPipe Pose Landmarker in VIDEO mode;
- MoveNet Thunder as a fast second opinion;
- RTMPose/MMPose for higher-quality offline comparison when needed.

Do not merge their outputs blindly. Use them to detect bad clips and bad frames.

Output:

```text
raw_mediapipe.jsonl
raw_movenet.jsonl
raw_rtmpose.jsonl
detector_agreement_scorecard.json
```

Minimum scorecard fields:

- frame coverage;
- mean visibility/presence;
- detector disagreement per joint;
- identity flip count;
- occlusion count;
- temporal jitter;
- foot/hand contact stability;
- rejected frame windows.

### Stage 3: 3D reconstruction and semantic labeling

For guide-ready avatar motion, prefer multi-view reconstruction or IK retarget.
Single-view world landmarks can be review evidence, but should not be the final
authority for hard movements.

Output:

```text
canonical_3d_motion.json
semantic_landmarks.jsonl
kinematic_scorecard.json
```

Kinematic scorecard should include:

- limb length stability;
- joint angle limits;
- smoothness/jerk;
- loop boundary delta;
- contact lock delta;
- side/primary identity stability;
- phase monotonicity;
- expected rep count;
- equipment path sanity where applicable.

### Stage 4: Avatar retarget

Retarget from canonical skeleton to the CamiFit avatar with IK constraints. Do
not directly copy noisy detector landmarks into the avatar path.

Output:

```text
Sources/CamiFitApp/Resources/MotionDemos/<exercise_id>.jsonl
Sources/CamiFitApp/Resources/MotionDemos/<exercise_id>.manifest.json
```

### Stage 5: Human visual review

Use the web gallery as the review surface, but add explicit decisions:

- app avatar looks anatomically plausible;
- detector video matches the source;
- avatar phase matches source phase;
- contact points are stable;
- no limb identity flips;
- no frame snap at loop boundary;
- no hidden source/provenance gap.

Output:

```text
visual_review.status = passed | failed
visual_review.reviewer
visual_review.evidence
visual_review.failure_reasons[]
```

### Stage 6: Engine replay and installed-app review

Only after visual review:

- replay through engine;
- verify rep count/hold timing;
- verify bundled app load path;
- verify installed app inventory.

### Stage 7: Artifact storage

The current local-only `dist/` dependency is a release risk. We need durable
storage before treating this as reproducible:

- object storage or GitHub Release asset bundle;
- manifest with sha256/bytes;
- restore script;
- CI/release strict audit after restore.

## Promotion Tiers

| Tier | Name | Product meaning |
|---|---|---|
| 0 | recommendation-only | Can appear in plans, no movement demo claim |
| 1 | source-candidate | Has source/search evidence, not app-renderable |
| 2 | detector-reviewable | Has source video plus detector review media |
| 3 | avatar-demo-candidate | Has app JSONL, not guide-ready |
| 4 | guide-ready | Passed provenance, visual, engine, and installed-app review |
| 5 | validation-ready | Also has multi-user runtime detector test set |

The important distinction: **guide-ready is not the same as validation-ready**.
Guide-ready means the demo motion is good enough to show. Validation-ready means
the live detector and rep/form logic have been tested against real variations.

## Immediate Recommendation

Stop promoting new exercises from opportunistic public-video extraction.

Next best move:

1. Keep the current 4 guide-ready traces visible but mark their source-chain
   artifact storage as a release infrastructure task.
2. Do not promote blocked visual-review candidates.
3. Capture first-party trainer footage for the next three movements:
   - `bodyweight_plank`
   - `machine_chest_supported_row`
   - `standing_miniband_hip_flexion`
4. Use two cameras for each capture if possible.
5. Add detector-agreement and kinematic scorecards before producing new app
   JSONLs.
6. Extend the web gallery to show:
   - visual review decision;
   - detector agreement score;
   - kinematic score;
   - source/capture session metadata;
   - explicit "why this is not guide-ready" reasons.

## Engineering Tasks

### P0: Make bad motion impossible to promote accidentally

- Add a `visual_review.status` hard gate for any app JSONL promotion.
- Add a `kinematic_scorecard.json` requirement for guide-ready traces.
- Fail promotion if loop/contact/identity metrics exceed thresholds.
- Fail promotion if detector review media is missing.

### P1: Make capture reproducible

- Add `capture_session.schema.json`.
- Add capture template files.
- Add a local recorder checklist for first-party trainer sessions.
- Add artifact restore/verify command for source-chain assets.

### P2: Improve the gallery into the review console

- Add side-by-side source video, detector skeleton, and avatar trace.
- Add frame-synchronized scrubbing.
- Add reviewer pass/fail controls that write a review JSON.
- Add scorecard chips for jitter, contact lock, phase, detector agreement, and
  loop closure.

### P3: Build validation sets separately from demos

- For each exercise, capture at least 5 validation clips across different body
  types, clothing, lighting, and camera positions.
- Keep validation clips out of the avatar demo path.
- Use validation clips to tune rep/form thresholds and runtime detector
  robustness.

## Data Sources Reviewed

- Google MediaPipe Pose Landmarker documentation:
  https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker
- TensorFlow MoveNet tutorial/model notes:
  https://www.tensorflow.org/hub/tutorials/movenet
- RTMPose paper:
  https://arxiv.org/abs/2303.07399
- AMASS project:
  https://amass.is.tue.mpg.de/
- OpenCap PLOS Computational Biology paper:
  https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1011462
- wger documentation/license notes:
  https://wger.readthedocs.io/en/latest/

## Decision

For CamiFit/Momentum, the ideal pipeline is:

```text
exercise contract
  -> first-party or vetted licensed source capture
  -> detector extraction with model agreement
  -> multi-view/IK canonical motion where needed
  -> semantic landmark labeling
  -> kinematic scorecard
  -> avatar retarget
  -> gallery visual review
  -> engine replay
  -> installed-app review
  -> durable artifact store
  -> guide-ready promotion
```

This is more work than the current pipeline, but it solves the right problem:
we stop asking a generic pose detector to be an animator, a biomechanics
reviewer, and a product QA system all at once.
