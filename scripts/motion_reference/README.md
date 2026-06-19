# Motion Reference Pipeline

This folder is the capture-to-viewer path for exercise demo motion. The shipped
`bodyweight_lunge` trace is a protected canonical example: use it as a golden
comparator for extraction experiments, not as a promotion target to overwrite.

## Scalable Coverage

Every packaged exercise should have a motion profile in
`exercise_motion_profiles.json` before we ship a guide trace for it. The profile
declares the exercise archetype, capture instructions, contact landmarks, phase
driver, required output landmarks, and QA gates.

Check the current coverage with:

```bash
scripts/motion_reference/audit_motion_coverage.py --strict
```

`--strict` fails for invalid bundled traces while allowing profiles that are
explicitly marked as `needs_reference_capture`. Use `--require-all-demos` when
the product milestone requires every preset to have a bundled trainer-reference
trace.

Some exercises also declare executable `quality_gates` in the profile registry.
Those gates are enforced automatically for accepted reference clips and reported
as `quality=pending_failed` while an exercise is still pending. To rehearse the
promotion gate against pending forensic traces, run:

```bash
scripts/motion_reference/audit_motion_coverage.py --strict --enforce-pending-quality-gates
```

For the current fail-closed product gate where every trackable/playable guide
must be backed by accepted reference data, while metadata-only capture-required
presets may remain packaged but non-trackable, use:

```bash
python3 scripts/motion_reference/test_audit_motion_coverage.py
scripts/motion_reference/audit_motion_coverage.py --strict --require-trackable-reference-clips --require-guide-ready-inventory
```

`--require-guide-ready-inventory` parses `AppExerciseTrackingGate.swift` and
requires the packaged playable JSONLs to exactly match the app's
`guideReadyPresetIDs`. It also rejects overlap with
`referenceCaptureRequiredPresetIDs`, requires every guide-ready exercise to have
a packaged preset/profile/manifest/accepted capture, and verifies accepted
`live_app_review` installed IDs/counts against the current packaged inventory.
The same gate also requires every pending motion profile to appear in
`referenceCaptureRequiredPresetIDs`, and rejects stale reference-capture IDs
that no longer have a pending profile.

For a future full-coverage milestone where every packaged preset must be backed
by accepted reference data, use:

```bash
scripts/motion_reference/audit_motion_coverage.py --strict --require-reference-clips
```

These stricter modes accept first-party captures, the protected lunge golden,
and licensed external workout clips with source/license/attribution metadata.
They treat temporary public references and canonical archetype traces as
incomplete, even when their JSONL geometry is structurally valid.

Accepted licensed external guide manifests must also carry source-search review
evidence. Use `rejected_candidates` when alternate clips were reviewed and
rejected; each entry must include a source URL or local source path, license,
attribution, rejected decision, and reason. If no rejected alternatives were
retained during promotion, use `rejected_sources` with
`status: none_retained_for_promotion_review`, a `review_scope`, and a `reason`.
The app runtime and strict audit both fail closed when a licensed external
guide lacks this ledger.

Pending/reference-capture-required profiles must carry the same source-search
ledger before they can sit in the app catalog. Strict audit checks packaged
pending presets and profile-only extras such as `bodyweight_jumping_jack` for
valid `rejected_candidates` entries or an explicit pending `rejected_sources`
record with `status: source_search_pending_fail_closed`. This does not make a
pending exercise guide-ready; it only proves the exercise remains quarantined
with documented search/rejection state.

Accepted guide manifests must also pin every source-preserving artifact in an
`artifact_integrity` object. Include `bytes` and `sha256` for `source_video`,
`raw_trace`, `normalizer`, and `output_trace`; include `candidate_trace`,
`golden_trace`, and `golden_comparison.*` artifacts when a protected comparator
is involved. The strict audit recomputes these values and fails if the ignored
`dist/` artifacts are missing or changed. On macOS, collect values with:

```bash
stat -f%z <artifact-path>
shasum -a 256 <artifact-path>
```

The protected Bodyweight Lunge golden is additionally pinned by the audit to
the approved packaged trace hash:
`04920c88fe91d6bd1c0c218bc8ae04477006bc97a6a1111e458d134f9f3a8a65`.
Changing `bodyweight_lunge.jsonl` or pointing `golden_trace` at an extracted
candidate fails the strict audit even if the manifest's mutable
`artifact_integrity` block is updated.

Accepted guide manifests also require `live_app_review` with `status: passed`,
human-readable evidence, the installed `app_bundle`, and the
`installed_playable_jsonls` count observed during the packaging/relaunch check.
It must also list `installed_playable_trace_ids`, and the current manifest's
`exercise_id` must be present in that list. The app runtime additionally binds
the adjacent manifest's `exercise_id` to the requested preset/JSONL ID before
loading a guide timeline, so a copied or mismatched manifest cannot unlock a
different trace. This is distinct from `visual_review`: visual review records
avatar/rig quality; live-app review records that the accepted trace survived
the packaged app path without expanding the trusted Trackable bundle.

Check the KG-to-viewer boundary with:

```bash
scripts/motion_reference/audit_kg_motion_readiness.py --summary-only
```

This audit separates app-runnable exercises from graph recommendation nodes. A
KG exercise is viewer-ready only when it maps to a packaged preset and that
preset has a valid motion profile plus bundled demo trace. Use
`--require-all-kg-viewer-ready` only for a future milestone where every KG
exercise must be displayable and measurable in the app.

For development experiments without accepted reference clips yet, compile a
deterministic archetype candidate:

```bash
scripts/motion_reference/compile_archetype_trace.py \
  --exercise-id bodyweight_plank
```

By default this writes to
`dist/motion-reference/archetype_candidates/<exercise_id>/<exercise_id>.jsonl`.
These traces are pipeline artifacts, not final trainer-reference data. Their
manifests stay marked as `canonical_archetype_trace` and
`canonical_archetype_candidate`.

The compiler refuses writes under
`Sources/CamiFitApp/Resources/MotionDemos` unless
`--allow-app-resource-output` is supplied, and it still refuses app-resource
writes for pending or rejected reference-capture profiles. Capture-required
exercises must stay candidate-only until exact accepted reference footage passes
source-chain, visual, engine, and live-app review.

## Contract

The app can render two motion sources:

- `procedural_fallback`: generated by `MotionDemoCompiler`, useful only until a
  real clip exists.
- `trainer_reference_trace`: bundled JSONL loaded from
  `Sources/CamiFitApp/Resources/MotionDemos/<exercise_id>.jsonl`.
- `licensed_external_reference_trace`: bundled JSONL derived from an external
  workout clip with source URL, license, attribution, raw trace, normalizer, and
  review artifacts preserved.

The production path is:

```text
licensed workout/trainer video
  -> MediaPipe Pose Landmarker VIDEO mode
  -> raw MediaPipe 33-landmark JSONL
  -> exercise-specific normalizer
  -> motion_demo_pose JSONL with primary/secondary/contact landmarks
  -> CamiFit avatar viewer
```

`motion_demo_pose` is still a `PoseFrame` shape, but it carries semantic labels
that raw MediaPipe does not know, such as `primary.knee` for the front knee and
`secondary.knee` for the support knee.

## Bodyweight Lunge Capture

Record a trainer doing a stationary side-view split lunge:

- full body visible from head to both feet;
- camera fixed, roughly hip height, true side view;
- front foot flat for the whole rep;
- support foot/toe planted for the whole rep;
- no swapping legs inside the clip;
- 2-3 clean reps at a controlled tempo.

For the current app preset, pick the visually front leg as `primary` and the rear
support leg as `secondary`.

## Commands

If you are recording locally, open the webcam recorder:

```bash
script/run_motion_reference_recorder.sh bodyweight_squat
```

The recorder saves each clip under
`dist/motion-reference/<exercise_id>/user_capture_<timestamp>/`.

Extract raw MediaPipe records:

```bash
scripts/motion_reference/export_mediapipe_reference_trace.py \
  --video /path/to/bodyweight-lunge-side-view.mov \
  --exercise-id bodyweight_lunge \
  --output-dir dist/motion-reference/bodyweight_lunge \
  --fps 15
```

The exporter writes `motion_reference_manifest.json` next to
`raw_mediapipe.jsonl`. Use its `next_steps` entries as the per-exercise command
contract: every capture gets a raw review command, but only exercises with a
capture-derived normalizer get a normalization command. Profiles that still
point at `compile_archetype_trace.py` are intentionally marked blocked until a
real reference-clip normalizer exists.

Normalize the raw trace into app-ready demo landmarks:

```bash
scripts/motion_reference/normalize_lunge_trace.py \
  --raw dist/motion-reference/bodyweight_lunge/raw_mediapipe.jsonl \
  --output dist/motion-reference/bodyweight_lunge/bodyweight_lunge.jsonl \
  --front-side right
```

For visualization-only review, you can skip this step and copy
`raw_mediapipe.jsonl` directly into `Resources/MotionDemos`. The app can decode
raw MediaPipe `pose` records. The tradeoff is that the raw trace has no reliable
front/support-leg labels for the engine.

The normalizer's default `--contact-policy lunge` preserves raw joint motion but
pins only the front foot and rear toe contact. It pins `x/y/z` for those contact
landmarks so the avatar loop does not slide or depth-pop. It does not pin the
rear heel, so the rear foot can naturally angle as the trainer descends. Use
`--contact-policy none` for a pure raw-plus-label trace, or `--contact-policy
feet` only when the source jitter visibly slides both feet.

## Bodyweight Lunge Golden Comparison

The app-bundled `bodyweight_lunge` JSONL and manifest are the ideal canonical
guide. Keep these files protected:

- `Sources/CamiFitApp/Resources/MotionDemos/bodyweight_lunge.jsonl`
- `Sources/CamiFitApp/Resources/MotionDemos/bodyweight_lunge.manifest.json`

The public-domain Wikimedia Commons clip below is useful as a validation
candidate for the extraction pipeline, not as an automatic replacement for the
golden lunge:

- source page:
  <https://commons.wikimedia.org/wiki/File:Strength_Training_Circuit-_Forward_Lunge.webm>
- source file:
  <https://upload.wikimedia.org/wikipedia/commons/5/57/Strength_Training_Circuit-_Forward_Lunge.webm>
- license: Public domain, U.S. Army / U.S. federal government work
- attribution used in manifests: Army Combat Fitness Test / U.S. Army via
  Wikimedia Commons

Reproduce the raw-preserved validation candidate:

```bash
mkdir -p dist/motion-reference/bodyweight_lunge/source
curl -L --fail \
  -o dist/motion-reference/bodyweight_lunge/source/commons-forward-lunge.webm \
  https://upload.wikimedia.org/wikipedia/commons/5/57/Strength_Training_Circuit-_Forward_Lunge.webm

scripts/motion_reference/export_mediapipe_reference_trace.py \
  --video dist/motion-reference/bodyweight_lunge/source/commons-forward-lunge.webm \
  --exercise-id bodyweight_lunge \
  --output-dir dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36 \
  --fps 15 \
  --start-ms 30000 \
  --end-ms 36000

scripts/motion_reference/normalize_lunge_trace.py \
  --raw dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36/raw_mediapipe.jsonl \
  --output dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36/bodyweight_lunge.raw_preserved.jsonl \
  --front-side right \
  --contact-policy lunge \
  --cycle-mode descent-mirror \
  --cycle-start-index 40 \
  --cycle-bottom-index 84 \
  --retarget raw \
  --fit-viewport \
  --source-kind licensed_external_reference_trace \
  --source-label "Wikimedia Commons Strength Training Circuit - Forward Lunge" \
  --source-page "https://commons.wikimedia.org/wiki/File:Strength_Training_Circuit-_Forward_Lunge.webm" \
  --source-media-url "https://upload.wikimedia.org/wikipedia/commons/5/57/Strength_Training_Circuit-_Forward_Lunge.webm" \
  --source-video dist/motion-reference/bodyweight_lunge/source/commons-forward-lunge.webm \
  --source-license "Public domain (U.S. Army / U.S. federal government work)" \
  --source-attribution "Army Combat Fitness Test / U.S. Army via Wikimedia Commons"

scripts/motion_reference/compare_trace_to_golden.py \
  --golden Sources/CamiFitApp/Resources/MotionDemos/bodyweight_lunge.jsonl \
  --candidate dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36/bodyweight_lunge.raw_preserved.jsonl \
  --output dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36/golden_comparison.json
```

Review the comparison output before trusting changes to the extractor. A raw
candidate may preserve source motion, fit the viewport, and pin planted contacts
while still failing to match the canonical lunge well enough for product use.
Do not copy raw-preserved lunge artifacts into app resources unless the product
decision is to replace the golden exemplar after side-by-side review.

## Bodyweight Plank External Clip

`bodyweight_plank` is backed by a licensed Pexels clip:

- source page:
  <https://www.pexels.com/video/a-woman-doing-plank-exercise-on-a-yoga-mat-7801720/>
- source file:
  <https://videos.pexels.com/video-files/7801720/7801720-uhd_2732_1154_25fps.mp4>
- license: Pexels License
- attribution used in manifests: Pexels / video 7801720

Reproduce the promoted static-hold trace:

```bash
mkdir -p dist/motion-reference/bodyweight_plank/source
uvx --from 'yt-dlp[default,curl-cffi]' yt-dlp \
  --extractor-args 'generic:impersonate' \
  -o 'dist/motion-reference/bodyweight_plank/source/a-woman-doing-plank-exercise-on-a-yoga-mat-7801720.%(ext)s' \
  'https://www.pexels.com/video/a-woman-doing-plank-exercise-on-a-yoga-mat-7801720/'

scripts/motion_reference/export_mediapipe_reference_trace.py \
  --video dist/motion-reference/bodyweight_plank/source/a-woman-doing-plank-exercise-on-a-yoga-mat-7801720.mp4 \
  --exercise-id bodyweight_plank \
  --output-dir dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6 \
  --fps 10 \
  --start-ms 0 \
  --end-ms 6000

scripts/motion_reference/render_mediapipe_trace_review.py \
  --raw dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6/raw_mediapipe.jsonl \
  --video dist/motion-reference/bodyweight_plank/source/a-woman-doing-plank-exercise-on-a-yoga-mat-7801720.mp4 \
  --output-dir dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6/raw_review \
  --fps 10

scripts/motion_reference/normalize_plank_trace.py \
  --raw dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6/raw_mediapipe.jsonl \
  --output dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6/bodyweight_plank.static_median.jsonl \
  --exercise-id bodyweight_plank \
  --primary-side left \
  --frame-count 31 \
  --source-label "Pexels woman doing plank exercise on a yoga mat" \
  --source-page "https://www.pexels.com/video/a-woman-doing-plank-exercise-on-a-yoga-mat-7801720/" \
  --source-media-url "https://videos.pexels.com/video-files/7801720/7801720-uhd_2732_1154_25fps.mp4" \
  --source-video dist/motion-reference/bodyweight_plank/source/a-woman-doing-plank-exercise-on-a-yoga-mat-7801720.mp4 \
  --source-license "Pexels License" \
  --source-attribution "Pexels / video 7801720"

cp dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6/bodyweight_plank.static_median.jsonl \
  Sources/CamiFitApp/Resources/MotionDemos/bodyweight_plank.jsonl
cp dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6/bodyweight_plank.static_median.manifest.json \
  Sources/CamiFitApp/Resources/MotionDemos/bodyweight_plank.manifest.json
```

The first reviewed Pexels plank candidate was rejected because MediaPipe placed
the lower-leg landmarks outside the image bounds. The promoted 7801720 clip
keeps the primary side visible and uses a static median of the external
MediaPipe hold window; for a plank hold, stable posture is the motion data.

## Bodyweight Pike External Clip

`bodyweight_pike` has a licensed Pexels source candidate, but it is currently
blocked from Trackable presets because installed-app fixed-frame review showed a
detached head/neck and broken avatar rig at the deepest pike frame. Keep these
artifacts under `dist/` as repair evidence until the avatar rig passes visual
review.

- source page:
  <https://www.pexels.com/video/yoga-flow-in-urban-loft-with-natural-light-31794279/>
- source file:
  <https://videos.pexels.com/video-files/31794279/13544679_2560_1440_24fps.mp4>
- license: Pexels License
- attribution used in manifests: K / Pexels video 31794279

Reproduce the candidate trace:

```bash
mkdir -p dist/motion-reference/bodyweight_pike/source_candidates
uvx --from 'yt-dlp[default,curl-cffi]' yt-dlp \
  --extractor-args 'generic:impersonate' \
  -o 'dist/motion-reference/bodyweight_pike/source_candidates/%(id)s.%(ext)s' \
  'https://www.pexels.com/video/yoga-flow-in-urban-loft-with-natural-light-31794279/'

scripts/motion_reference/export_mediapipe_reference_trace.py \
  --video dist/motion-reference/bodyweight_pike/source_candidates/yoga-flow-in-urban-loft-with-natural-light-31794279.mp4 \
  --exercise-id bodyweight_pike \
  --output-dir dist/motion-reference/bodyweight_pike/pexels_pike_31794279_800_3200 \
  --fps 12 \
  --start-ms 800 \
  --end-ms 3200

scripts/motion_reference/render_mediapipe_trace_review.py \
  --raw dist/motion-reference/bodyweight_pike/pexels_pike_31794279_800_3200/raw_mediapipe.jsonl \
  --video dist/motion-reference/bodyweight_pike/source_candidates/yoga-flow-in-urban-loft-with-natural-light-31794279.mp4 \
  --output-dir dist/motion-reference/bodyweight_pike/pexels_pike_31794279_800_3200/raw_review \
  --fps 12

scripts/motion_reference/normalize_pike_trace.py \
  --raw dist/motion-reference/bodyweight_pike/pexels_pike_31794279_800_3200/raw_mediapipe.jsonl \
  --output dist/motion-reference/bodyweight_pike/pexels_pike_31794279_800_3200/bodyweight_pike.raw_preserved.jsonl \
  --exercise-id bodyweight_pike \
  --primary-side right \
  --cycle-start-index 3 \
  --cycle-bottom-index 28 \
  --top-pad-frames 4 \
  --fit-viewport \
  --source-start-ms 800 \
  --source-label "Pexels yoga flow in urban loft with natural light" \
  --source-page "https://www.pexels.com/video/yoga-flow-in-urban-loft-with-natural-light-31794279/" \
  --source-media-url "https://videos.pexels.com/video-files/31794279/13544679_2560_1440_24fps.mp4" \
  --source-video dist/motion-reference/bodyweight_pike/source_candidates/yoga-flow-in-urban-loft-with-natural-light-31794279.mp4 \
  --source-license "Pexels License" \
  --source-attribution "K / Pexels video 31794279"

CAMIFIT_GUIDE_EXERCISE=bodyweight_pike \
CAMIFIT_ALLOW_FIXED_GUIDE_FRAME=1 \
CAMIFIT_GUIDE_FRAME_MS=2407 \
./script/build_and_run.sh --verify
```

Do not copy the candidate JSONL into `Sources/CamiFitApp/Resources/MotionDemos`.
The candidate preserves the MediaPipe side-view joint motion for the clean source
segment, fits it into the app viewport, pins planted hand/toe contacts, and
mirrors the source descent to close a top-bottom-top loop, but the current avatar
rig review failed. Promotion requires a fixed head/neck/torso rig screenshot at
the deepest frame plus loop and engine replay evidence. Rejected source
candidates included a Pexels plank/up-down plank clip with no pike phase and an
oblique yoga-flow clip whose raw top angle never reached the preset's long-plank
threshold.

## Suspension Tricep Press External Clip

`suspension_tricep_press` is backed by a licensed Pexels clip:

- source page:
  <https://www.pexels.com/video/a-woman-doing-push-up-8435987/>
- source file:
  <https://videos.pexels.com/video-files/8435987/8435987-hd_1920_1080_25fps.mp4>
- license: Pexels License
- attribution used in manifests: Pexels / video 8435987

Reproduce the promoted trace:

```bash
mkdir -p dist/motion-reference/suspension_tricep_press/pexels_8435987
curl -L --fail -A 'Mozilla/5.0' \
  -e 'https://www.pexels.com/video/a-woman-doing-push-up-8435987/' \
  -o dist/motion-reference/suspension_tricep_press/pexels_8435987/woman_suspension_tricep_press_8435987.mp4 \
  'https://www.pexels.com/download/video/8435987/'

scripts/motion_reference/export_mediapipe_reference_trace.py \
  --video dist/motion-reference/suspension_tricep_press/pexels_8435987/woman_suspension_tricep_press_8435987.mp4 \
  --exercise-id suspension_tricep_press \
  --output-dir dist/motion-reference/suspension_tricep_press/pexels_8435987/extract_4500_10000 \
  --fps 12 \
  --start-ms 4500 \
  --end-ms 10000

scripts/motion_reference/render_mediapipe_trace_review.py \
  --raw dist/motion-reference/suspension_tricep_press/pexels_8435987/extract_4500_10000/raw_mediapipe.jsonl \
  --video dist/motion-reference/suspension_tricep_press/pexels_8435987/woman_suspension_tricep_press_8435987.mp4 \
  --output-dir dist/motion-reference/suspension_tricep_press/pexels_8435987/extract_4500_10000/raw_review \
  --fps 12

scripts/motion_reference/normalize_suspension_tricep_press_trace.py \
  --raw dist/motion-reference/suspension_tricep_press/pexels_8435987/extract_4500_10000/raw_mediapipe.jsonl \
  --output dist/motion-reference/suspension_tricep_press/pexels_8435987/extract_4500_10000/suspension_tricep_press.external.jsonl \
  --exercise-id suspension_tricep_press \
  --primary-side left \
  --fit-viewport \
  --cycle-mode extension-mirror \
  --source-start-ms 4500 \
  --source-end-ms 10000 \
  --source-kind licensed_external_reference_trace \
  --source-label "Pexels side-view suspension trainer tricep press" \
  --source-page "https://www.pexels.com/video/a-woman-doing-push-up-8435987/" \
  --source-media-url "https://videos.pexels.com/video-files/8435987/8435987-hd_1920_1080_25fps.mp4" \
  --source-video dist/motion-reference/suspension_tricep_press/pexels_8435987/woman_suspension_tricep_press_8435987.mp4 \
  --source-license "Pexels License" \
  --source-attribution "Pexels / video 8435987"

cp dist/motion-reference/suspension_tricep_press/pexels_8435987/extract_4500_10000/suspension_tricep_press.external.jsonl \
  Sources/CamiFitApp/Resources/MotionDemos/suspension_tricep_press.jsonl
cp dist/motion-reference/suspension_tricep_press/pexels_8435987/extract_4500_10000/suspension_tricep_press.external.manifest.json \
  Sources/CamiFitApp/Resources/MotionDemos/suspension_tricep_press.manifest.json
```

The promoted trace uses the camera-side left arm from the reviewed source
segment. The clip contains one clean flexed-to-extended press-out half-cycle;
the normalizer mirrors that half-cycle to close the app guide loop as
flexed-extended-flexed. Raw review showed a stable full-body side view, no
identity swaps, no neck blow-up, and a shoulder-hip-ankle line held above 165
degrees.

## Single-Arm Dumbbell Preacher Curl External Clip

`single_arm_dumbbell_preacher_curl` is backed by a licensed Pixabay clip:

- source page:
  <https://pixabay.com/videos/crossfit-gym-workout-training-66991/>
- license: Pixabay Content License
- attribution: tixonov_valentin / Pixabay
- local clip:
  `dist/motion-reference/single_arm_dumbbell_preacher_curl/pixabay_66991/crossfit_gym_workout_training_66991.mp4`

Accepted trace reproduction:

```bash
scripts/motion_reference/export_mediapipe_reference_trace.py \
  --video dist/motion-reference/single_arm_dumbbell_preacher_curl/pixabay_66991/crossfit_gym_workout_training_66991.mp4 \
  --exercise-id single_arm_dumbbell_preacher_curl \
  --output-dir dist/motion-reference/single_arm_dumbbell_preacher_curl/pixabay_66991/extract_0_24916 \
  --fps 10

scripts/motion_reference/normalize_single_arm_dumbbell_preacher_curl_trace.py \
  --raw dist/motion-reference/single_arm_dumbbell_preacher_curl/pixabay_66991/extract_0_24916/raw_mediapipe.jsonl \
  --output dist/motion-reference/single_arm_dumbbell_preacher_curl/pixabay_66991/extract_0_24916/single_arm_dumbbell_preacher_curl.external.jsonl \
  --video dist/motion-reference/single_arm_dumbbell_preacher_curl/pixabay_66991/crossfit_gym_workout_training_66991.mp4 \
  --cycle-start-index 41 \
  --cycle-flex-index 56 \
  --cycle-end-index 64 \
  --primary-side right

python3 scripts/motion_reference/render_mediapipe_trace_review.py \
  --raw dist/motion-reference/single_arm_dumbbell_preacher_curl/pixabay_66991/extract_0_24916/single_arm_dumbbell_preacher_curl.external.jsonl \
  --video dist/motion-reference/single_arm_dumbbell_preacher_curl/pixabay_66991/crossfit_gym_workout_training_66991.mp4 \
  --output-dir dist/motion-reference/single_arm_dumbbell_preacher_curl/pixabay_66991/extract_0_24916/external_review \
  --fps 10

cp dist/motion-reference/single_arm_dumbbell_preacher_curl/pixabay_66991/extract_0_24916/single_arm_dumbbell_preacher_curl.external.jsonl \
  Sources/CamiFitApp/Resources/MotionDemos/single_arm_dumbbell_preacher_curl.jsonl
cp dist/motion-reference/single_arm_dumbbell_preacher_curl/pixabay_66991/extract_0_24916/single_arm_dumbbell_preacher_curl.external.manifest.json \
  Sources/CamiFitApp/Resources/MotionDemos/single_arm_dumbbell_preacher_curl.manifest.json
```

The raw source segment uses frames `41..56..64` (`4100..5600..6400ms`) from the
right/camera-side arm. Raw MediaPipe has the correct phase but visible dumbbell
occlusion shortens the wrist path, so the promoted guide uses source timing and
an anatomical retarget: planted upper arm, constant forearm length, and a short
extended settle so the bundled EMA-filtered engine replay counts one rep.

## Bodyweight Jumping Jack Rejected External Clip

`bodyweight_jumping_jack` is currently **not guide-ready**. The Pexels 7299359
retarget remains only under `dist/motion-reference/...` as rejected forensic
evidence while a better licensed reference clip/source-preserving extraction is
found. There is intentionally no bundled
`Sources/CamiFitApp/Resources/MotionDemos/bodyweight_jumping_jack.jsonl`.
Do not use this section as an accepted promotion recipe.

Rejected Pexels video 7299359 source:

- source page:
  <https://www.pexels.com/video/elderly-man-doing-jumping-jacks-outside-7299359/>
- source download: <https://www.pexels.com/download/video/7299359/>
- license: Pexels License
- attribution: Kindel Media / Pexels
- local clip:
  `dist/motion-reference/bodyweight_jumping_jack/pexels_7299359/elderly_man_jumping_jacks_outside_7299359.mp4`

Rejected trace reproduction:

```bash
mkdir -p dist/motion-reference/bodyweight_jumping_jack/pexels_7299359
curl -L --fail \
  -o dist/motion-reference/bodyweight_jumping_jack/pexels_7299359/elderly_man_jumping_jacks_outside_7299359.mp4 \
  https://www.pexels.com/download/video/7299359/

scripts/motion_reference/export_mediapipe_reference_trace.py \
  --video dist/motion-reference/bodyweight_jumping_jack/pexels_7299359/elderly_man_jumping_jacks_outside_7299359.mp4 \
  --exercise-id bodyweight_jumping_jack \
  --output-dir dist/motion-reference/bodyweight_jumping_jack/pexels_7299359/extract_0_full \
  --fps 12

python3 scripts/motion_reference/normalize_jumping_jack_trace.py \
  --raw dist/motion-reference/bodyweight_jumping_jack/pexels_7299359/extract_0_full/raw_mediapipe.jsonl \
  --video dist/motion-reference/bodyweight_jumping_jack/pexels_7299359/elderly_man_jumping_jacks_outside_7299359.mp4 \
  --output dist/motion-reference/bodyweight_jumping_jack/pexels_7299359/extract_0_full/bodyweight_jumping_jack.source_timed_anatomical.jsonl \
  --cycle-start-index 98 \
  --cycle-open-index 105 \
  --cycle-end-index 112 \
  --retarget-mode anatomical \
  --endpoint-min-confidence 0.75 \
  --min-confidence 0.75 \
  --foot-min-confidence 0.75 \
  --open-wrist-min 0.55 \
  --source-label "Pexels 7299359 Elderly Man Doing Jumping Jacks Outside" \
  --source-page https://www.pexels.com/video/elderly-man-doing-jumping-jacks-outside-7299359/ \
  --source-file-url https://www.pexels.com/download/video/7299359/ \
  --source-license "Pexels License" \
  --source-attribution "Kindel Media / Pexels"

python3 scripts/motion_reference/render_mediapipe_trace_review.py \
  --raw dist/motion-reference/bodyweight_jumping_jack/pexels_7299359/extract_0_full/bodyweight_jumping_jack.source_timed_anatomical.jsonl \
  --video dist/motion-reference/bodyweight_jumping_jack/pexels_7299359/elderly_man_jumping_jacks_outside_7299359.mp4 \
  --output-dir dist/motion-reference/bodyweight_jumping_jack/pexels_7299359/extract_0_full/source_timed_anatomical_review \
  --fps 12

cp dist/motion-reference/bodyweight_jumping_jack/pexels_7299359/extract_0_full/bodyweight_jumping_jack.source_timed_anatomical.manifest.json \
  Sources/CamiFitApp/Resources/MotionDemos/bodyweight_jumping_jack.manifest.json
```

The rejected trace uses the Pexels source as timing/phase reference, but it
does not preserve enough source shape for an app-visible guide. User review and
subagent critique rejected it because the open frame turns into a straight
high-V instead of the source's bent overhead arms, the feet mostly slide
laterally, the closed knees stay too wide for closed feet, and wrist/elbow
motion still pops between frames. The app now treats `bodyweight_jumping_jack`
as `pending_licensed_reference_clip`; chat/routine guide activation must fail
closed until a replacement passes source-shape residual, foot-lift, closed-leg,
and smoothness gates.
The bundled manifest is tagged `rejected_after_user_visual_review`, and
`MotionDemoBundleStore` must refuse it for guide playback. The build script also
fails if `bodyweight_jumping_jack.jsonl` is accidentally packaged while this
status remains rejected.

Rejected candidate notes:

- The old Wikimedia Commons `Jumping jack movimiento.ogg` trace remains rejected
  because it used the source clip only as a scalar phase driver, included
  unrelated arm-raise poses after the jumping-jack frames, and retargeted onto a
  canned front-view skeleton instead of preserving workout motion.
- Pexels 4764124 was rechecked after a source-search pass ranked it as the best
  visual candidate. The video shows real front-view jumping jacks, but the local
  pose extraction remains rejected: review frames show floating head/face
  landmarks, unstable lower limbs, and arm/foot phase mismatch. Local evidence:
  `dist/motion-reference/bodyweight_jumping_jack/pexels_4764124/source_contact_sheet.jpg`,
  `.../extract_0_6200/raw_video_review_sheet.jpg`, and
  `.../extract_0_6200/raw_review_sheet.jpg`.
- Pexels 7746545 was rejected despite strong visual framing because raw
  MediaPipe arm landmarks were ambiguous around jacket/hair/background edges.
- Pexels 6326725 right-subject crop was rejected after app review because the
  normalized trace collapsed the closed-frame feet, produced rubbery arm/torso
  motion, and required a forced endpoint correction of `0.305178`, above the
  `0.08` promotion gate.
- Pexels 7299359 remains rejected after multiple app reviews. The final
  packaged retarget passed JSON/replay tests but still failed visible guide
  review: apex shape diverged from the source, feet slid, closed legs looked
  pinched, and adjacent arm motion was spiky.
- The first source-timed Pexels 7299359 anatomical pass was rejected after app
  review because it still produced a starfish-like apex: hands were far outside
  the shoulders instead of meeting overhead like the source frame.
- The second source-timed Pexels 7299359 anatomical pass was rejected after app
  review because it overcorrected into a synthetic puppet: fixed head/torso
  anchors, perfectly flat ankle rails, elbows collapsed too early, and closed
  wrists tucked through the torso.
- Future Jumping Jack promotion must pass the executable `quality_gates` in
  `scripts/motion_reference/exercise_motion_profiles.json`: open-frame and
  transition wrist spread, closed knee/ankle anatomy, adjacent wrist/elbow
  smoothness, visible ankle vertical travel, and a source-shape residual that
  compares the packaged `source_frame_id` frame against the raw MediaPipe
  source frame.

Rejected Wikimedia reproduction:

```bash
mkdir -p dist/motion-reference/bodyweight_jumping_jack/commons_jumping_jack_movimiento
curl -L --fail \
  -o dist/motion-reference/bodyweight_jumping_jack/commons_jumping_jack_movimiento/jumping_jack_movimiento.ogg \
  https://upload.wikimedia.org/wikipedia/commons/a/a7/Jumping_jack_movimiento.ogg

scripts/motion_reference/export_mediapipe_reference_trace.py \
  --video dist/motion-reference/bodyweight_jumping_jack/commons_jumping_jack_movimiento/jumping_jack_movimiento.ogg \
  --exercise-id bodyweight_jumping_jack \
  --output-dir dist/motion-reference/bodyweight_jumping_jack/commons_jumping_jack_movimiento \
  --fps 12

scripts/motion_reference/normalize_jumping_jack_trace.py \
  --raw dist/motion-reference/bodyweight_jumping_jack/commons_jumping_jack_movimiento/raw_mediapipe.jsonl \
  --video dist/motion-reference/bodyweight_jumping_jack/commons_jumping_jack_movimiento/jumping_jack_movimiento.ogg \
  --output dist/motion-reference/bodyweight_jumping_jack/commons_jumping_jack_movimiento/bodyweight_jumping_jack.normalized.jsonl \
  --cycle-start-index 0 \
  --cycle-end-index 18 \
  --interval-ms 100
```

The rejected normalizer extracted phase from raw wrist height plus ankle spread
and retargeted it onto the canonical front-view jumping-jack rig. Viewer recheck
rejected that approach: the source clip includes unrelated arm-raise poses after
the jumping-jack frames, and the app bundle discards the raw body motion by
driving a canned skeleton from one scalar phase value. Keep this artifact only
as rejection evidence.

## Resistance Band Reverse Curl Candidate Rejection

Reviewed Pexels video 6326763 as a possible
`resistance_band_reverse_curl` reference:

- source page:
  <https://www.pexels.com/video/men-working-out-together-using-a-resistance-band-6326763/>
- license: Pexels License
- attribution: Pavel Danilyuk / Pexels video 6326763
- local source:
  `dist/motion-reference/resistance_band_reverse_curl/pexels_6326763/resistance_band_duo_6326763.mp4`

Rejected for guide promotion. The motion is visibly a resistance-band curl, but
the crop does not prove the pronated grip that makes it a reverse curl. The
normal crop isolates the athlete better but clips/low-confidences the working
arm during flexion; the wide crop preserves slightly more hand context but does
not fix the wrist-tracking issue and increases partner-hand intrusion risk.
Promoting either trace would teach generic elbow flexion rather than accurate
reverse-curl motion.

Review artifacts:

- normal crop raw review:
  `dist/motion-reference/resistance_band_reverse_curl/pexels_6326763/extract_18000_23500/raw_review_sheet.jpg`
- wide crop raw review:
  `dist/motion-reference/resistance_band_reverse_curl/pexels_6326763/extract_wide_18000_23500/raw_review_sheet.jpg`

Reproduction commands:

```bash
scripts/motion_reference/export_mediapipe_reference_trace.py \
  --video dist/motion-reference/resistance_band_reverse_curl/pexels_6326763/left_subject_crop.mp4 \
  --exercise-id resistance_band_reverse_curl \
  --output-dir dist/motion-reference/resistance_band_reverse_curl/pexels_6326763/extract_18000_23500 \
  --fps 12 \
  --start-ms 18000 \
  --end-ms 23500

scripts/motion_reference/export_mediapipe_reference_trace.py \
  --video dist/motion-reference/resistance_band_reverse_curl/pexels_6326763/left_subject_wide_crop.mp4 \
  --exercise-id resistance_band_reverse_curl \
  --output-dir dist/motion-reference/resistance_band_reverse_curl/pexels_6326763/extract_wide_18000_23500 \
  --fps 12 \
  --start-ms 18000 \
  --end-ms 23500
```

## Standing Miniband Hip Flexion Candidate Rejections

`standing_miniband_hip_flexion` is still **not guide-ready**. The required
source is a side-view standing miniband hip-flexion cycle: working knee down,
knee drives forward/up, then returns down while the stance foot stays planted.

The following licensed Pexels candidates were downloaded and contact-sheeted
under `dist/motion-reference/standing_miniband_hip_flexion/source_candidates/`;
all remain rejected:

- Pexels 8416674, SHVETS production / Pexels:
  tight band/hand/thigh crop, not enough full-body hip/knee/ankle evidence.
- Pexels 8837226, MART PRODUCTION / Pexels:
  standing miniband lateral hip abduction, not forward hip flexion.
- Pexels 8836976, MART PRODUCTION / Pexels:
  standing miniband lateral abduction from a front/oblique crop, not side-view
  knee-drive hip flexion.
- Pexels 7477907, Angela Roma / Pexels:
  lying floor leg-band work, not standing hip flexion.

Contact-sheet evidence:

- `dist/motion-reference/standing_miniband_hip_flexion/source_candidates/a-female-person-working-out-with-a-resistance-band-8416674_fps2_sheet.jpg`
- `dist/motion-reference/standing_miniband_hip_flexion/source_candidates/a-woman-exercising-her-legs-with-a-resistance-band-8837226_fps2_sheet.jpg`
- `dist/motion-reference/standing_miniband_hip_flexion/source_candidates/woman-doing-a-leg-exercise-using-a-resistance-band-8836976_fps2_sheet.jpg`
- `dist/motion-reference/standing_miniband_hip_flexion/source_candidates/women-using-resistance-band-for-leg-workout-7477907_fps2_sheet.jpg`

## Machine Chest-Supported Row External Clip Candidate

`machine_chest_supported_row` currently keeps the Wikimedia Commons import of
Colossus Fitness's machine T-bar row video as candidate evidence only:

- source page:
  <https://commons.wikimedia.org/wiki/File:How_to_properly_do_Machine_T-Bar_Rows.webm>
- source media:
  <https://upload.wikimedia.org/wikipedia/commons/3/3d/How_to_properly_do_Machine_T-Bar_Rows.webm>
- original source: <https://www.youtube.com/watch?v=TyLoy3n_a10>
- license: CC BY 3.0 claimed by the import, but Commons still marks the file
  `License review needed`
- attribution: Colossus Fitness via Wikimedia Commons
- candidate segment: `84.0s-91.0s`

Candidate trace reproduction:

```bash
mkdir -p dist/motion-reference/machine_chest_supported_row/commons_machine_tbar_row
curl -L --fail \
  -o dist/motion-reference/machine_chest_supported_row/commons_machine_tbar_row/source.webm \
  https://upload.wikimedia.org/wikipedia/commons/3/3d/How_to_properly_do_Machine_T-Bar_Rows.webm

python3 scripts/motion_reference/export_mediapipe_reference_trace.py \
  --video dist/motion-reference/machine_chest_supported_row/commons_machine_tbar_row/source.webm \
  --exercise-id machine_chest_supported_row \
  --output-dir dist/motion-reference/machine_chest_supported_row/commons_machine_tbar_row/extract_84000_91000 \
  --fps 12 \
  --start-ms 84000 \
  --end-ms 91000

python3 scripts/motion_reference/normalize_machine_chest_supported_row_trace.py \
  --raw dist/motion-reference/machine_chest_supported_row/commons_machine_tbar_row/extract_84000_91000/raw_mediapipe.jsonl \
  --output dist/motion-reference/machine_chest_supported_row/commons_machine_tbar_row/extract_84000_91000/machine_chest_supported_row.external.jsonl \
  --source-video dist/motion-reference/machine_chest_supported_row/commons_machine_tbar_row/source.webm \
  --source-license "CC BY 3.0 claimed by source import; Commons marks license review needed" \
  --source-attribution "Colossus Fitness via Wikimedia Commons"

python3 scripts/motion_reference/render_mediapipe_trace_review.py \
  --raw dist/motion-reference/machine_chest_supported_row/commons_machine_tbar_row/extract_84000_91000/machine_chest_supported_row.external.jsonl \
  --output-dir dist/motion-reference/machine_chest_supported_row/commons_machine_tbar_row/extract_84000_91000/external_review \
  --fps 12
```

Do not copy this candidate JSONL into
`Sources/CamiFitApp/Resources/MotionDemos/machine_chest_supported_row.jsonl`
while the Commons page still requires license review. The packaged app may keep
`machine_chest_supported_row.manifest.json` as metadata with
`acceptance_status=pending_source_license_review` and
`playable_trace_packaged=false`, but Trackable presets and routine execution
must treat the exercise as reference-capture-required until the source license
review is resolved and the trace is re-reviewed.

## 2026-06-09 Pending Reference Candidate Rejections

The following reviewed candidates are intentionally not promoted. Keep the
corresponding exercises in `pending_licensed_reference_clip` until an exact,
pose-readable reference clip is found.

- `bench_lying_single_arm_dumbbell_tricep_extension`: Pexels 29569378 is
  licensed/free-to-use, but the local sheet
  `dist/motion-reference/bench_lying_single_arm_dumbbell_tricep_extension/candidate_search/pexels_29569378/source_fps2_sheet.jpg`
  shows an incline bilateral dumbbell press, not a lying single-arm triceps
  extension. Pexels 6286166 is also rejected because it is an upright overhead
  triceps extension. wger exercise 245 video 60 is license-defensible bench
  dumbbell skullcrusher footage, and was extracted/reviewed at
  `dist/motion-reference/bench_lying_single_arm_dumbbell_tricep_extension/wger_245_video60/extract_12000_18700/raw_mediapipe.jsonl`
  with review sheet
  `dist/motion-reference/bench_lying_single_arm_dumbbell_tricep_extension/wger_245_video60/extract_12000_18700/raw_review_sheet.jpg`.
  It remains rejected because it is bilateral rather than single-arm, with
  MediaPipe dropout/low-confidence arm landmarks in the reviewed segment.
  wger exercise 211 video 57 is also license-defensible, but its contact sheet
  `dist/motion-reference/bench_lying_single_arm_dumbbell_tricep_extension/source_candidates/wger_211_video57/source_fps2_sheet.jpg`
  shows a seated/incline overhead single-arm triceps extension, not the
  bench-lying pattern required by this preset.
- `single_arm_chest_supported_incline_row`: the latest search found only
  non-permissive or non-downloadable semantic near-misses
  (Exercises.com.au, Trainest, Tenor) plus Commons row sources that are
  unsupported bent-over/T-bar rows rather than chest-supported incline
  dumbbell rows. Each retained candidate now records source page, license
  status, attribution, rejected decision, and reason so a future promotion
  cannot skip the source-review trail.
- `single_arm_cable_tricep_extension`: the local Pexels candidate under
  `dist/motion-reference/single_arm_cable_tricep_extension/pexels_5319432/`
  is semantically close, but not promotion-ready. Public provenance appears to
  be Pexels 5319433, the local manifest lacks source metadata, and raw
  MediaPipe does not reliably satisfy the preset's `left` shoulder/elbow/wrist
  plus hip contract. The wger exercise 95 video 50 candidate is openly licensed
  but is a cable biceps curl, not a triceps extension.
- `wide_grip_preacher_curl_with_ez_bar`: wger exercise 465 is openly licensed
  and its exercise record describes an SZ/EZ-bar preacher curl. Video 53 was
  extracted through MediaPipe at
  `dist/motion-reference/wide_grip_preacher_curl_with_ez_bar/wger_465_video53/extract_0_12000/raw_mediapipe.jsonl`
  and reviewed at
  `dist/motion-reference/wide_grip_preacher_curl_with_ez_bar/wger_465_video53/extract_0_12000/raw_review_sheet.jpg`.
  The camera-side elbow cycle is trackable, but the video still reads as a
  plate-loaded/preacher-station variation and does not prove the exact
  wide-grip free EZ-bar setup, so it remains rejected. Video 54 remains rejected
  as a dumbbell/handle variation. Wikimedia's EZ-bar curl video is standing,
  not preacher-supported. A YouTube search found exact-looking wide-grip EZ-bar
  preacher-curl clips, but `yt-dlp` reported `license=NA`, so they were not
  eligible for ingestion.
- `standing_miniband_hip_flexion` and `resistance_band_reverse_curl`: the
  latest stock/open-source search found only generic band-leg, hip-flexion
  hold, generic band-curl, or non-downloadable/non-permissive sources. Do not
  promote those as exact guide motion.

Capture-required presets must not package playable canonical-archetype JSONL
fallbacks. Keep the preset and pending manifest metadata, but leave
`Sources/CamiFitApp/Resources/MotionDemos/<exercise_id>.jsonl` absent until an
exact licensed source plus source-preserving normalizer passes review. The
app build script fails if one of those placeholder traces is accidentally
bundled.

- `bodyweight_jumping_jack`: Wikimedia Commons
  `File:Jumping_jack_Animation.gif` is CC-BY-SA 4.0, but it is an animated
  illustration/self-published clip rather than workout footage with human pose
  evidence, so it is rejected for accepted guide extraction. The profile-only
  quarantine ledger also records the rejected Pexels and Coverr real-workout
  candidates whose pose, shape-gate, or license-caveat reviews failed.
- `bodyweight_pike`: the Pexels yoga-flow candidate stays
  `blocked_visual_rig_review_failed`; installed-app fixed-frame review showed
  detached head/neck deformation at the deepest pike frame. The manifest may
  retain source metadata and a rejected-candidate record, but no playable app
  JSONL may ship until the rig review is repaired and re-verified.

If a future lunge source clip contains one clean descent but the ascent is
polluted by walking, resets, or camera cuts, generate a candidate loop from the
clean descent:

```bash
scripts/motion_reference/normalize_lunge_trace.py \
  --raw dist/motion-reference/bodyweight_lunge/raw_mediapipe.jsonl \
  --output dist/motion-reference/bodyweight_lunge/bodyweight_lunge.jsonl \
  --front-side right \
  --contact-policy lunge \
  --cycle-mode descent-mirror \
  --cycle-start-index 40 \
  --cycle-bottom-index 84 \
  --retarget raw \
  --fit-viewport
```

Prefer a full clean trainer rep when available. The mirrored-descent mode is a
reviewed repair for otherwise usable reference clips, not the default product
capture path. Compare any lunge candidate to the shipped golden lunge before
considering promotion:

```bash
scripts/motion_reference/compare_trace_to_golden.py \
  --golden Sources/CamiFitApp/Resources/MotionDemos/bodyweight_lunge.jsonl \
  --candidate dist/motion-reference/bodyweight_lunge/bodyweight_lunge.jsonl \
  --output dist/motion-reference/bodyweight_lunge/golden_comparison.json
```

Use `--retarget canonical-lunge` only as an internal fallback when raw MediaPipe
image-space coordinates recover phase and timing but fail visual display review.
Do not promote that fallback as source-derived guide motion when a raw-preserved
trace passes viewport, contact, loop, and replay gates.

Inspect candidates in the motion-review app before any explicit replacement
decision. The current app bundle should continue to use the protected lunge
golden trace:

```bash
CAMIFIT_GUIDE_EXERCISE=bodyweight_lunge ./script/build_and_run.sh --verify
```

If a lunge candidate fails visual review or golden comparison, keep it under
`dist/motion-reference/` as extractor evidence and leave the bundled guide
untouched.

## Bodyweight Squat Capture

For a side-view squat capture, extract raw MediaPipe records from the saved
webcam movie, let the squat normalizer detect the clean bottom/top, and render
the review:

```bash
scripts/motion_reference/export_mediapipe_reference_trace.py \
  --video dist/motion-reference/bodyweight_squat/user_capture_20260606-013521/bodyweight_squat_reference.mov \
  --exercise-id bodyweight_squat \
  --output-dir dist/motion-reference/bodyweight_squat/user_capture_20260606-013521 \
  --fps 15

scripts/motion_reference/normalize_squat_trace.py \
  --raw dist/motion-reference/bodyweight_squat/user_capture_20260606-013521/raw_mediapipe.jsonl \
  --video dist/motion-reference/bodyweight_squat/user_capture_20260606-013521/bodyweight_squat_reference.mov \
  --output dist/motion-reference/bodyweight_squat/user_capture_20260606-013521/bodyweight_squat.normalized.jsonl \
  --exercise-id bodyweight_squat

scripts/motion_reference/render_mediapipe_trace_review.py \
  --raw dist/motion-reference/bodyweight_squat/user_capture_20260606-013521/bodyweight_squat.normalized.jsonl \
  --video dist/motion-reference/bodyweight_squat/user_capture_20260606-013521/bodyweight_squat_reference.mov \
  --output-dir dist/motion-reference/bodyweight_squat/user_capture_20260606-013521/normalized_review
```

The squat normalizer uses the high-confidence camera-side landmarks to detect a
clean bottom/top window, repairs short MediaPipe knee/ankle teleports for phase
estimation, and mirrors the captured ascent into a top-bottom-top loop. By
default it retargets that phase onto a canonical side-view squat rig with
planted feet and realistic segment lengths. Use `--retarget raw` only for
debugging the capture; raw MediaPipe coordinates are not suitable as the final
avatar display body.

## Bodyweight Push-up Capture

For a side-view push-up capture, extract raw MediaPipe records from the saved
webcam movie, normalize the clean top-bottom-top cycle, and render the review:

```bash
scripts/motion_reference/export_mediapipe_reference_trace.py \
  --video dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/bodyweight_pushup_reference.mov \
  --exercise-id bodyweight_pushup \
  --output-dir dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504 \
  --fps 15

scripts/motion_reference/normalize_pushup_trace.py \
  --raw dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/raw_mediapipe.jsonl \
  --video dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/bodyweight_pushup_reference.mov \
  --output dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/bodyweight_pushup.normalized.jsonl \
  --exercise-id bodyweight_pushup \
  --cycle-start-index 54 \
  --cycle-end-index 104 \
  --close-loop \
  --mirror-x

scripts/motion_reference/render_mediapipe_trace_review.py \
  --raw dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/bodyweight_pushup.normalized.jsonl \
  --video dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/bodyweight_pushup_reference.mov \
  --output-dir dist/motion-reference/bodyweight_pushup/user_capture_20260606-005504/normalized_review
```

The push-up normalizer uses the high-confidence camera-side landmarks as
`primary.*`, pins the planted wrist/heel/toe contacts, smooths the captured
cycle, mirrors the guide to face right, and synthesizes a stable depth-offset
`secondary.*` side for the viewer. Do not use the raw far-side MediaPipe joints
for the guide when they are visibly occluded in a side-view clip.

## Acceptance Checks

For the lunge viewer, reject the trace if:

- the front heel or toe slides or lifts;
- the support toe slides;
- either knee bends backward in the side-view projection;
- the torso collapses forward;
- the motion looks like a leg swap instead of a stationary lunge;
- the app engine no longer counts a rep when replaying the frames.
