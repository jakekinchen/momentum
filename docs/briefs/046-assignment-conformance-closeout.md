# Assignment Conformance Closeout

**Status:** implemented with visual-regression demotion complete
**Date:** 2026-06-06
**Branch:** active worktree currently reports `main`; AGENTS guidance still
names `feat/monorepo-synthesis` as the intended synthesis lane.
**Current pulled head:** `c8ef92b Hide skeleton when camera is off`

## Source Of Truth

The assignment requirements are the vendored golden snapshot at:

- `data/golden/candidate-assessment/ASSESSMENT.md`
- `data/golden/candidate-assessment/README.md`
- `data/golden/candidate-assessment/PROVENANCE.md`
- `data/golden/candidate-assessment/data/exercises.json`
- `data/golden/candidate-assessment/data/member-context.json`

`PROVENANCE.md` pins the snapshot to upstream commit
`4b8c67246a659c26bd222079c5c7829d295acad9`, fetched on 2026-06-04. Treat this
snapshot as the requirements floor. Do not edit it to make product behavior
look compliant.

## Current Assessment

### 2026-06-09 Motion Truth

The live product truth has been reset after viewer review. Older entries in
this brief that promoted Jumping Jack, Pike, or other synthetic/new traces are
historical and superseded by this section.

- Trackable presets are limited to four guide-ready app presets:
  `bodyweight_lunge`, `bodyweight_pushup`, `bodyweight_squat`, and
  `single_arm_cable_tricep_extension`.
- `machine_chest_supported_row` is demoted to reference-capture-required
  metadata only. The retained Commons/YouTube candidate is not Trackable while
  the Commons source page still marks the imported file as `License review
  needed`; no playable app JSONL ships for Machine Row.
- `bodyweight_jumping_jack` is hard-quarantined after live viewer rejection:
  no packaged preset, JSONL, or manifest is bundled in the app.
- `bodyweight_pike` is not Trackable. The visual-rig review failed because the
  avatar head/neck detached around the high-hip frame. Its preset and manifest
  remain metadata only, and no playable JSONL ships.
- `bodyweight_plank`, `single_arm_dumbbell_preacher_curl`, and
  `suspension_tricep_press` are not Trackable after installed-app fixed-frame
  visual regression review. Their manifests remain as review metadata only,
  and no playable JSONL ships for any of the three.
- The original lunge guide is protected as the golden comparator. The shipped
  trace was restored from the pre-replacement 107-frame guide, then minimally
  loop-closed by appending frame 0 as the final frame. The approved shipped
  hash is
  `04920c88fe91d6bd1c0c218bc8ae04477006bc97a6a1111e458d134f9f3a8a65`.
  The later 89-frame Commons extraction remains only a validation candidate
  under `dist/motion-reference/`.
- Packaged-app resource discovery no longer probes the launch current
  directory for presets, recorded runs, or live-worker paths. `tccutil reset
  SystemPolicyDocumentsFolder com.camifit.app` followed by
  `./script/build_and_run.sh --verify` produced a clean
  `/Applications/Momentum.app` launch without a Documents-folder prompt.
- Chat activation now reads its supported exercise IDs from the same app gate
  that defines the four guide-ready presets. `bodyweight_jumping_jack`,
  `bodyweight_pike`, `bodyweight_plank`, `machine_chest_supported_row`,
  `single_arm_dumbbell_preacher_curl`, `suspension_tricep_press`, and the other
  reference-capture-required presets are
  absent from coach activation instructions and remain blocked by local action
  validation.

The repo is strongest on deterministic KG behavior and now has the assignment
path wired into the live app chat surface. The remaining limits are documented
as product scope boundaries rather than hidden compliance gaps.

Confirmed strengths:

- The golden exercise catalog is imported into generated Python KG artifacts:
  50 exercises, 19 muscle groups, 9 loaded body regions, 36 movement patterns,
  and 32 equipment terms.
- The generated member graph represents all required Jordan Rivera sections:
  profile, goals, preferences, equipment, injuries, workout history,
  adherence, biomarkers, labs, chat history, and coach brief.
- Python assessment-focused tests pass with `uv run python -m pytest`.
- Swift KGKit parity tests pass for resolver, safety, alternatives, workout
  generation, overlay state, and oracle conformance.
- The repo preserves the key invariant: deterministic graph traversal decides
  eligibility and safety; the LLM may parse or verbalize but must not decide.

Closed in this slice:

- Added a Swift-loadable assignment artifact:
  `Sources/KGKit/Resources/Artifact/kg_artifact.assessment.v0.json`, generated
  from the full 50-exercise assessment graph with source hashes and version
  metadata.
- Added a Swift-loadable member graph artifact:
  `Sources/KGKit/Resources/Artifact/assessment_member_kg.generated.json`.
- Routed coach workout requests through `AssignmentWorkoutPlanner` and
  `KGKit.WorkoutGenerator` before Codex freeform prose.
- Added `KGWorkoutPlanCard` presentation evidence for selected exercises,
  filtered exercises, graph paths, reason codes, alternatives, and app preset
  mapping status.
- Added `AssignmentCopilotProvider` and `AssignmentCopilotFactCardView` for the
  required brief, adherence, sleep, changed-since-last-week, message-pattern,
  churn-risk, and no-supporting-fact prompts.
- Documented ontology grounding as an intentional unverified subset plus a
  production RDF/SKOS/PROV-O/SHACL path.
- Added deterministic confidence/method metadata and local typo aliases for the
  resolver without relaxing safety-critical blocks.
- Updated active Python gate commands to `uv run python -m pytest`.

Residual limits:

- The Copilot surface is a chat fact-card surface, not a richer standalone
  production dashboard.
- Most generated KG exercises remain recommendation-only for avatar
  guide/measurement until curated app preset and motion-profile mappings are
  reviewed. Current KG motion readiness reports 4 guide-ready app presets; the
  generated 50-exercise catalog reports 1 exact `guide_ready` row, 14
  `archetype_demo_only` rows, 35 `recommend_only` rows, and 18 mapped-incomplete
  rows. Squat and push-up remain first-party webcam references. Lunge is the
  protected golden reference. Cable tricep extension is the only retained
  licensed external guide. Machine Row is blocked by unresolved Commons license
  review. Jumping Jack is hard-quarantined after visible user rejection. Pike,
  plank, suspension tricep press, and preacher curl are blocked by visual-rig
  failure, and the remaining bundled-but-guide-less presets stay out of
  Trackable presets and runnable routine blocks until exact licensed reference
  clips pass replay, visual, and audit gates.
- Accepted licensed external guide clips now require a structured
  rejected-source ledger before promotion. `rejected_candidates` records
  reviewed clips that failed source/pose/semantic quality; `rejected_sources`
  records the explicit case where no rejected alternatives were retained during
  promotion. Both the strict Python audit and the app manifest guide gate fail
  closed when a licensed external guide lacks this source-search review record.
- `graph/ontology-lock.json` remains unverified; no SNOMED/OPE/COPPER release,
  access-date, license, or concept-ID claim is treated as verified.

## Work Plan

## Execution Log

### 2026-06-06 Progress

- Started from `/Users/kelly/Developer/camifit-app` on
  `feat/monorepo-synthesis`; initial git status showed this brief as an
  untracked file and no other app-worktree changes.
- Ran `git worktree list --porcelain` and confirmed this worktree is the active
  `feat/monorepo-synthesis` lane.
- Ran `bash scripts/agent_thread_status.sh` from `kg-canonical/`; the KG
  subtree still had `<stop-orchestrator/>`, so this assignment closeout is being
  treated as fresh human-approved resume direction before KG product files are
  changed.
- Spawned four read-only subagents for independent probes: Python gates/docs,
  assessment graph promotion, app workout/provenance/copilot wiring, and
  resolver/motion/ontology coverage. Main-thread review of their findings is
  incorporated into the implementation below.
- Confirmed the generated assessment exercise graph already exists at
  `kg-canonical/graph/generated/assessment_exercise_kg.generated.json` with 212
  nodes / 512 edges preserving all 50 golden exercises, while the bundled Swift
  runtime artifact remains the 28-node seed graph.
- Created and validated the KG subtree resume brief at
  `kg-canonical/docs/briefs/017-assignment-conformance-closeout.md`, updated
  `kg-canonical/GOAL.md`, and recorded executor evidence in
  `kg-canonical/docs/session-logs/018-executor-assignment-conformance-closeout.md`.
- Reviewed the four subagent probes and folded their concrete findings into the
  implementation: module-form pytest gates, full graph promotion, app planner
  routing, provenance UI, resolver metadata, motion-readiness reporting, and the
  Swift reverse `PART_OF` knee traversal fix.
- Added the root README assignment closeout section and kept deeper examples,
  tradeoffs, AI-use notes, failure modes, and production evaluation details in
  `kg-canonical/README.md`.
- Fixed `scripts/run_monorepo_gates.sh` so generated-artifact validation checks
  before-vs-after generator idempotence instead of requiring a clean diff
  against `HEAD` during an uncommitted implementation slice.

### 2026-06-06 Validation Evidence

```bash
(cd kg-canonical && uv run python -m pytest)
# 153 passed

(cd kg-canonical && uv run python -m kg.validation)
# validation_status: pass
# schema_validation_status: pass
# ontology_status: todo_unverified
# verified: false

(cd kg-canonical && uv run python -m kg.assessment_import)
# status: pass
# exercise_count: 50
# generated_exercise_node_count: 212
# generated_exercise_edge_count: 512
# member_sections_missing: []

swift test --disable-sandbox
# 273 tests passed

swift test --disable-sandbox --filter KGKitTests
# 61 tests passed

scripts/motion_reference/audit_motion_coverage.py --strict
# presets=4 profiles=4 pending_reference_captures=0 failures=0

scripts/motion_reference/audit_kg_motion_readiness.py --summary-only
# generated kg_exercises=50 guide_ready=0 archetype_demo_only=25
# recommend_only=25 mapped_incomplete=0
# generated_missing=0

(cd kg-canonical && bash scripts/validate_resume_brief.sh docs/briefs/017-assignment-conformance-closeout.md)
(cd kg-canonical && bash scripts/audit_autonomous_workflow.sh)
(cd kg-canonical && node scripts/audit_codex_pair_state.mjs)
git diff --check
# clean / pass

scripts/run_monorepo_gates.sh
# pass: kg Python tests, kg.validation, kg.assessment_import, artifact
# idempotence, Swift conformance parity, full swift test, motion coverage,
# KG motion readiness, and contracts listing
```

### 2026-06-08 Motion/Exercise Coverage Follow-Up

Superseded for `bodyweight_jumping_jack` by the 2026-06-08 viewer recheck and
hard-quarantine entry below.

- Added `bodyweight_jumping_jack` as a packaged app preset in both root
  `Presets/` and bundled app resources.
- Added runtime support for the documented geometry DSL helpers needed by the
  preset (`distance`, `ratio`, `min`, `max`, `midpoint`,
  `angle_to_horizontal`, and `signed_angle`) with Swift evaluator coverage.
- Added a front-view jumping-jack canonical archetype to
  `scripts/motion_reference/compile_archetype_trace.py`; the generated app
  MotionDemos JSONL/manifest were later rejected and removed from the bundle.
- Mapped `Exercise:jumping_jack` to `bodyweight_jumping_jack` as exact
  coverage for the Exercises tab; the viewer recheck later demoted it to
  recommend-only/reference-capture-required.
- Extended the existing bundled squat motion trace top hold so the real
  `bodyweight_squat` preset replay counts one rep through the engine after EMA
  filtering.
- Updated app allowlists/build verification for
  `bodyweight_jumping_jack`, including coach action instructions, the
  motion-reference recorder, and packaged resource verification.
- Relaunched the installed app from `/Applications/Momentum.app`; this earlier
  bundle check was superseded by the hard-quarantine relaunch below.
- Added `standing_miniband_hip_flexion` as the next exact guide-ready KG
  exercise because the current pose DSL can measure side-view left-leg hip
  flexion, torso posture, lifted-knee bend, and right stance-leg stability
  without claiming camera visibility for miniband tension.
- Added the root and bundled preset, canonical `standing_hip_flexion` compiler
  archetype, generated bundled motion JSONL/manifest, recorder instructions,
  coach allowlist text, packaged-resource verification, exercise-tab mapping,
  and routine-projection coverage.
- Added tests proving the clean hip-flexion trace counts one rep, a shallow
  trace counts zero, the bundled JSONL replays through the real engine, the
  Exercises tab marks the KG exercise guide-ready, and a KG-generated routine
  projects `Exercise:standing_miniband_hip_flexion` into the runnable
  `standing_miniband_hip_flexion` preset through the normal prompt equipment
  resolver path (`only miniband`), not a test-only equipment override.
- Reviewed the hip-flexion slice with a read-only subagent and addressed its
  main findings by aligning the preset to the KG's `left_leg` side and proving
  routine projection through the production prompt-equipment path. Remaining
  release hygiene note: the repo has many untracked files in this active
  worktree, so a future commit must stage the new preset/demo/test files
  deliberately.
- Refreshed `/Applications/Momentum.app` and `/Applications/Future Coach.app`
  from the verified `dist/Momentum.app` at 2026-06-08 17:20:38 local time; the
  running process is the installed
  `/Applications/Momentum.app/Contents/MacOS/CamiFitApp` bundle and both
  installed bundles contain the jumping-jack and hip-flexion preset, JSONL, and
  manifest resources.
- Reviewed a read-only subagent shortlist for the next exact-tracking slice.
  It independently ranked `Exercise:resistance_band_reverse_curl` first because
  side-view shoulder/elbow/wrist landmarks honestly measure the elbow
  flexion-extension cycle while band tension and pronated grip remain
  non-visual.
- Added `resistance_band_reverse_curl` as an exact guide-ready preset for
  `Exercise:resistance_band_reverse_curl`, including root and bundled presets,
  a `standing_reverse_curl` canonical archetype compiler path, bundled JSONL
  and manifest resources, recorder instructions, coach allowlist text, app
  preset discovery coverage, exercise-tab mapping, and routine-projection
  tests.
- Added local resolver aliases for `loop band` and `resistance band loop` in
  both Swift KGKit and the Python oracle so prompts such as `Only resistance
  band loop` produce hard `allowed_equipment_only` constraints against
  `Equipment:resistance_band_loop`.
- Proved routine projection through the normal prompt equipment resolver path:
  `Build an arms routine. only resistance band loop.` selects
  `Exercise:resistance_band_reverse_curl` and projects it into the runnable
  `resistance_band_reverse_curl` preset.
- Refreshed `/Applications/Momentum.app` and `/Applications/Future Coach.app`
  again from the verified `dist/Momentum.app` at 2026-06-08 17:33:08 local
  time; both installed bundles contain the jumping-jack, hip-flexion, and
  reverse-curl preset, JSONL, and manifest resources, and the running process is
  `/Applications/Momentum.app/Contents/MacOS/CamiFitApp`.
- Reviewed a read-only subagent check for `Exercise:bodyweight_pike`; it agreed
  the side-view high-plank-to-pike cycle is an honest exact-tracking candidate
  when scoped to primary shoulder, elbow, wrist, hip, knee, and ankle landmarks,
  and called out that hand/foot contact should remain setup/demo QA rather than
  a runtime form claim.
- Added `bodyweight_pike` as an exact guide-ready preset for
  `Exercise:bodyweight_pike`, including root and bundled presets, the
  `bodyweight_pike` canonical archetype trace, bundled JSONL and manifest
  resources, recorder instructions, coach allowlist text, app preset discovery
  coverage, exercise-tab mapping, and routine-projection tests.
- Tightened the planner safety overlay so wrist/shoulder/elbow/forearm memory
  blocks `bodyweight_pike` alongside hand-loaded plank and pushup presets.
- Proved normal prompt projection with `Build a core pike routine. only yoga
  mat.`; it selects `Exercise:bodyweight_pike`, maps it to `bodyweight_pike`
  with `guide_ready` readiness, and compiles a runnable pike block.
- Added `single_arm_dumbbell_preacher_curl` as an exact guide-ready preset for
  `Exercise:single_arm_dumbbell_preacher_curl`, including root and bundled
  presets, a `preacher_curl` canonical archetype compiler path, bundled JSONL
  and manifest resources, recorder instructions, coach allowlist text, app
  preset discovery coverage, exercise-tab mapping, and routine-projection
  tests.
- Scoped preacher-curl tracking honestly: the engine measures the side-view
  shoulder/elbow/wrist elbow-flexion cycle and upper-arm stability; dumbbell
  load and preacher-bench support remain setup/equipment requirements rather
  than pose-visible claims.
- Proved normal prompt projection with `Build an arms preacher curl routine.
  only dumbbell and preacher curl bench.`; it selects
  `Exercise:single_arm_dumbbell_preacher_curl`, maps it to
  `single_arm_dumbbell_preacher_curl` with `guide_ready` readiness, and
  compiles a runnable preacher-curl block.
- Reviewed a read-only subagent check for
  `Exercise:bench_lying_single_arm_dumbbell_tricep_extension`; it confirmed the
  honest trackable scope is side-view elbow flexion-extension ROM, rep count,
  coarse upper-arm steadiness, and a coarse lying torso/bench line. Dumbbell
  load, bench contact, skull clearance, grip/wrist rotation, and out-of-plane
  shoulder drift remain setup/visual-review constraints rather than runtime
  pose claims.
- Added `bench_lying_single_arm_dumbbell_tricep_extension` as an exact
  guide-ready preset for
  `Exercise:bench_lying_single_arm_dumbbell_tricep_extension`, including root
  and bundled presets, a `lying_tricep_extension` canonical archetype compiler
  path, bundled JSONL and manifest resources, recorder instructions, coach
  allowlist text, app preset discovery coverage, exercise-tab mapping, and
  routine-projection tests.
- Fixed the new preset's posture-signal endpoint order after focused replay
  showed clean frames reporting the mirror angle. The clean trace now reports
  `upper_arm_tilt` near 43 degrees and `torso_tilt` near 9 degrees, so the
  upper-arm and bench-line rules pass without weakening the rep-count logic.
- Proved normal prompt projection with `Build an arms tricep extension routine.
  only dumbbell and flat bench.`; it selects
  `Exercise:bench_lying_single_arm_dumbbell_tricep_extension`, maps it to
  `bench_lying_single_arm_dumbbell_tricep_extension` with `guide_ready`
  readiness, and compiles a runnable tricep-extension block.
- Reviewed a read-only subagent check for
  `Exercise:single_arm_cable_tricep_extension`; it confirmed exact tracking is
  honest only for the pose-visible side-view elbow extension-return cycle,
  upper-arm steadiness, and torso posture. Cable stack/load, handle attachment,
  cable path, attachment height, grip, and true 3D elbow position remain
  setup/equipment or visual-review constraints, not runtime pose claims.
- Added `single_arm_cable_tricep_extension` as an exact guide-ready preset for
  `Exercise:single_arm_cable_tricep_extension`, including root and bundled
  presets, a `standing_cable_tricep_extension` canonical archetype compiler
  path, bundled JSONL and manifest resources, recorder instructions, coach
  allowlist text, app preset discovery coverage, exercise-tab mapping, and
  routine-projection tests.
- Tightened both left-arm tricep exact presets
  (`bench_lying_single_arm_dumbbell_tricep_extension` and
  `single_arm_cable_tricep_extension`) to use `left.shoulder`, `left.elbow`,
  `left.wrist`, and `left.hip` instead of generic `primary.*` landmarks, so
  the KG `left_arm` side claim is enforced by the preset signals and bundled
  motion manifests.
- Proved normal prompt projection with `Build an arms cable tricep routine.
  only cable resistance machine and handle attachment.`; it selects
  `Exercise:single_arm_cable_tricep_extension`, maps it to
  `single_arm_cable_tricep_extension` with `guide_ready` readiness, and
  compiles a runnable cable-tricep-extension block.
- Reviewed the next-candidate shortlist with a read-only subagent; it agreed
  `Exercise:suspension_tricep_press` was the best immediate exact-tracking
  candidate before this slice, and ranked wide-grip EZ-bar preacher curl,
  single-arm chest-supported incline row, and high-plank bird dog as likely
  next candidates after suspension is counted.
- Added `suspension_tricep_press` as an exact guide-ready preset for
  `Exercise:suspension_tricep_press`, including root and bundled presets, a
  `suspension_tricep_press` canonical archetype compiler path, bundled JSONL
  and manifest resources, recorder instructions, coach allowlist text, app
  preset discovery coverage, exercise-tab mapping, and routine-projection
  tests.
- Scoped suspension-tricep-press tracking honestly: the engine measures the
  side-view elbow press-out/return cycle, a long shoulder-hip-ankle body line,
  and upper-arm alignment with the torso. Strap anchor, handle grip, suspension
  load, and strap path remain setup/equipment requirements rather than
  pose-visible runtime claims.
- Proved normal prompt projection with `Build an arms suspension tricep
  routine. only suspension trainer.`; it selects
  `Exercise:suspension_tricep_press`, maps it to
  `suspension_tricep_press` with `guide_ready` readiness, and compiles a
  runnable suspension-tricep-press block.
- Reviewed a read-only subagent check for
  `Exercise:wide_grip_preacher_curl_with_ez_bar`; it confirmed exact tracking
  is honest only for the side-view camera-side elbow flexion/extension cycle,
  upper-arm steadiness, and torso posture. EZ-bar presence, load, grip width,
  both-arm symmetry, wrist angle, and preacher-bench contact remain
  setup/equipment requirements rather than runtime pose claims.
- Added `wide_grip_preacher_curl_with_ez_bar` as an exact guide-ready preset
  for `Exercise:wide_grip_preacher_curl_with_ez_bar`, including root and
  bundled presets, reuse of the `preacher_curl` canonical archetype compiler
  path, bundled JSONL and manifest resources, recorder instructions, coach
  allowlist text, app preset discovery coverage, exercise-tab mapping, and
  routine-projection tests.
- Added a narrow `preacher` intent filter in `KGKit.WorkoutGenerator` so the
  user prompt reaches the preacher-curl candidate pool before equipment and
  safety filtering; this avoids treating wide-grip EZ-bar preacher curl as a
  merely safe but out-of-routine selected candidate.
- Proved normal prompt projection with `Build an arms wide-grip preacher curl
  routine. only ez bar and preacher curl bench.`; it selects
  `Exercise:wide_grip_preacher_curl_with_ez_bar`, maps it to
  `wide_grip_preacher_curl_with_ez_bar` with `guide_ready` readiness, and
  compiles a runnable wide-grip EZ-bar preacher-curl block.
- Reviewed a read-only subagent check for
  `Exercise:single_arm_chest_supported_incline_row`; it confirmed promotion is
  honest when scoped to the left side-view shoulder/elbow/wrist/hip row cycle,
  left shoulder path, and torso posture. Dumbbell load, bench incline, chest
  contact, grip/path quality, and real-camera accuracy remain setup,
  visual-review, or future validation claims rather than current runtime
  guarantees.
- Added `single_arm_chest_supported_incline_row` as an exact guide-ready preset
  for `Exercise:single_arm_chest_supported_incline_row`, including root and
  bundled presets, a `chest_supported_row` canonical archetype compiler path,
  bundled JSONL and manifest resources, recorder instructions, coach allowlist
  text, app preset discovery coverage, exercise-tab mapping, and
  routine-projection tests.
- Added a word-aware row/upper-back/lats intent filter in Swift KGKit and the
  Python oracle so row prompts reach the row candidate pool, while guarding
  against the `lat` substring matching unrelated text such as `flat bench`.
- Proved normal prompt projection with `Build an upper-back row routine. only
  dumbbell and adjustable bench - incline.`; it selects
  `Exercise:single_arm_chest_supported_incline_row`, maps it to
  `single_arm_chest_supported_incline_row` with `guide_ready` readiness, and
  compiles a runnable row block.

Validation evidence:

```bash
swift test --disable-sandbox
# 339 tests passed

(cd kg-canonical && uv run python -m pytest)
# 155 passed

scripts/motion_reference/audit_motion_coverage.py --strict
# presets=14 profiles=14 pending_reference_captures=0 failures=0

scripts/motion_reference/audit_kg_motion_readiness.py --summary-only \
  --write-report scripts/motion_reference/kg_motion_readiness.assessment.v0.json
# app_presets=14 app_guide_ready=14
# generated kg_exercises=50 guide_ready=10 archetype_demo_only=23
# recommend_only=17 mapped_incomplete=0 generated_missing=0

scripts/motion_reference/compile_archetype_trace.py --exercise-id bodyweight_pike
# compiled bodyweight_pike JSONL, 17 frames

scripts/motion_reference/compile_archetype_trace.py --exercise-id single_arm_dumbbell_preacher_curl
# compiled single_arm_dumbbell_preacher_curl JSONL, 17 frames

scripts/motion_reference/compile_archetype_trace.py --exercise-id bench_lying_single_arm_dumbbell_tricep_extension
# compiled bench_lying_single_arm_dumbbell_tricep_extension JSONL, 17 frames

scripts/motion_reference/compile_archetype_trace.py --exercise-id single_arm_cable_tricep_extension
# compiled single_arm_cable_tricep_extension JSONL, 17 frames

scripts/motion_reference/compile_archetype_trace.py --exercise-id suspension_tricep_press
# compiled suspension_tricep_press JSONL, 17 frames

scripts/motion_reference/compile_archetype_trace.py --exercise-id wide_grip_preacher_curl_with_ez_bar
# compiled wide_grip_preacher_curl_with_ez_bar JSONL, 17 frames

scripts/motion_reference/compile_archetype_trace.py --exercise-id single_arm_chest_supported_incline_row
# compiled single_arm_chest_supported_incline_row JSONL, 17 frames

swift test --disable-sandbox --filter ResistanceBandReverseCurlAcceptanceTests \
  --filter MotionDemoTimelineTests/testResistanceBandReverseCurlDemoTimelineCountsOneRep \
  --filter MediaPipePoseProviderTests/testBundledCanonicalMotionDemoTracesDecodeAndReplayThroughEngine \
  --filter AssignmentExerciseCatalogTests \
  --filter AssignmentWorkoutPlannerTests/testExactGuideReadyReverseCurlProjectsIntoRunnableRoutine \
  --filter ResolverTests/testOnlyResistanceBandLoopAlias
# 11 selected Swift tests passed

(cd kg-canonical && uv run python -m pytest tests/test_resolver.py -q)
# 12 passed

swift test --disable-sandbox --filter BodyweightPikeAcceptanceTests \
  --filter MotionDemoTimelineTests/testBodyweightPikeDemoTimelineKeepsHandsAndToesPlantedAndCountsOneRep \
  --filter MediaPipePoseProviderTests/testBundledCanonicalMotionDemoTracesDecodeAndReplayThroughEngine \
  --filter AssignmentExerciseCatalogTests \
  --filter AssignmentWorkoutPlannerTests/testExactGuideReadyBodyweightPikeProjectsIntoRunnableRoutine \
  --filter AssignmentWorkoutPlannerTests/testSavedWristMemoryKeepsLowerBodyRoutineLungeFirstAndExcludesPlank \
  --filter AssignmentWorkoutPlannerTests/testWristMemoryBlocksHandLoadedPikeRoutineProjection \
  --filter AppExerciseSessionViewModelTests/testDefaultViewModelDiscoversPackagedPresetResources \
  --filter AppExerciseSessionViewModelTests/testLoadsBundledPresetListAndSelectsSquatAndPlank
# 15 selected Swift tests passed

swift test --disable-sandbox --filter SingleArmDumbbellPreacherCurlAcceptanceTests \
  --filter MotionDemoTimelineTests/testSingleArmDumbbellPreacherCurlDemoTimelineCountsOneRep \
  --filter MediaPipePoseProviderTests/testBundledCanonicalMotionDemoTracesDecodeAndReplayThroughEngine \
  --filter AssignmentExerciseCatalogTests \
  --filter AssignmentWorkoutPlannerTests/testExactGuideReadyPreacherCurlProjectsIntoRunnableRoutine \
  --filter AppExerciseSessionViewModelTests/testDefaultViewModelDiscoversPackagedPresetResources \
  --filter AppExerciseSessionViewModelTests/testLoadsBundledPresetListAndSelectsSquatAndPlank
# 14 selected Swift tests passed

swift test --disable-sandbox --filter BenchLyingSingleArmDumbbellTricepExtensionAcceptanceTests \
  --filter MotionDemoTimelineTests/testBenchLyingSingleArmDumbbellTricepExtensionDemoTimelineCountsOneRep \
  --filter MediaPipePoseProviderTests/testBundledCanonicalMotionDemoTracesDecodeAndReplayThroughEngine \
  --filter AssignmentExerciseCatalogTests \
  --filter AssignmentWorkoutPlannerTests/testExactGuideReadyBenchLyingTricepExtensionProjectsIntoRunnableRoutine \
  --filter AppExerciseSessionViewModelTests/testDefaultViewModelDiscoversPackagedPresetResources \
  --filter AppExerciseSessionViewModelTests/testLoadsBundledPresetListAndSelectsSquatAndPlank
# 15 selected Swift tests passed

swift test --disable-sandbox --filter SingleArmCableTricepExtensionAcceptanceTests \
  --filter MotionDemoTimelineTests/testSingleArmCableTricepExtensionDemoTimelineCountsOneRep \
  --filter MediaPipePoseProviderTests/testBundledCanonicalMotionDemoTracesDecodeAndReplayThroughEngine \
  --filter AssignmentExerciseCatalogTests \
  --filter AssignmentWorkoutPlannerTests/testExactGuideReadySingleArmCableTricepExtensionProjectsIntoRunnableRoutine \
  --filter AppExerciseSessionViewModelTests/testDefaultViewModelDiscoversPackagedPresetResources \
  --filter AppExerciseSessionViewModelTests/testLoadsBundledPresetListAndSelectsSquatAndPlank
# 16 selected Swift tests passed

focused left-arm tricep replay/projection suite
# 19 selected Swift tests passed after tightening both exact tricep presets to
# left-side landmarks

swift test --disable-sandbox --filter SuspensionTricepPressAcceptanceTests \
  --filter MotionDemoTimelineTests/testSuspensionTricepPressDemoTimelineCountsOneRepAndKeepsBodyLineLong \
  --filter MediaPipePoseProviderTests/testBundledCanonicalMotionDemoTracesDecodeAndReplayThroughEngine \
  --filter AssignmentExerciseCatalogTests \
  --filter AssignmentWorkoutPlannerTests/testExactGuideReadySuspensionTricepPressProjectsIntoRunnableRoutine \
  --filter AppExerciseSessionViewModelTests/testDefaultViewModelDiscoversPackagedPresetResources \
  --filter AppExerciseSessionViewModelTests/testLoadsBundledPresetListAndSelectsSquatAndPlank
# 17 selected Swift tests passed

swift test --disable-sandbox --filter WideGripPreacherCurlWithEZBarAcceptanceTests \
  --filter MotionDemoTimelineTests/testWideGripPreacherCurlWithEZBarDemoTimelineCountsOneRep \
  --filter MediaPipePoseProviderTests/testBundledCanonicalMotionDemoTracesDecodeAndReplayThroughEngine \
  --filter AssignmentExerciseCatalogTests \
  --filter AssignmentWorkoutPlannerTests/testExactGuideReadyWideGripPreacherCurlWithEZBarProjectsIntoRunnableRoutine \
  --filter AppExerciseSessionViewModelTests/testDefaultViewModelDiscoversPackagedPresetResources \
  --filter AppExerciseSessionViewModelTests/testLoadsBundledPresetListAndSelectsSquatAndPlank
# 18 selected Swift tests passed

swift test --disable-sandbox --filter SingleArmChestSupportedInclineRowAcceptanceTests \
  --filter MotionDemoTimelineTests/testSingleArmChestSupportedInclineRowDemoTimelineCountsOneRep \
  --filter MediaPipePoseProviderTests/testBundledCanonicalMotionDemoTracesDecodeAndReplayThroughEngine \
  --filter AssignmentExerciseCatalogTests \
  --filter AssignmentWorkoutPlannerTests/testExactGuideReadySingleArmChestSupportedInclineRowProjectsIntoRunnableRoutine \
  --filter AppExerciseSessionViewModelTests/testDefaultViewModelDiscoversPackagedPresetResources \
  --filter AppExerciseSessionViewModelTests/testLoadsBundledPresetListAndSelectsSquatAndPlank
# 19 selected Swift tests passed

swift test --disable-sandbox --filter WorkoutGeneratorTests \
  --filter AssignmentWorkoutPlannerTests/testExactGuideReadyBenchLyingTricepExtensionProjectsIntoRunnableRoutine \
  --filter AssignmentWorkoutPlannerTests/testExactGuideReadySingleArmChestSupportedInclineRowProjectsIntoRunnableRoutine
# 6 selected Swift tests passed, including the word-aware row/lat regression

(cd kg-canonical && uv run python -m pytest tests/test_workout_generator.py -q)
# 9 passed

./script/build_and_run.sh --verify
# built, signed, and verified dist/Momentum.app

installed bundle refresh/resource check
# /Applications/Momentum.app and /Applications/Future Coach.app refreshed
# 2026-06-08 18:55:22 CDT /Applications/Momentum.app
# 2026-06-08 18:55:22 CDT /Applications/Future Coach.app
# installed resources include all fourteen app presets and motion demos:
# bodyweight_squat, bodyweight_lunge, bodyweight_pushup, bodyweight_plank,
# bodyweight_jumping_jack, standing_miniband_hip_flexion,
# resistance_band_reverse_curl, bodyweight_pike, and
# single_arm_dumbbell_preacher_curl,
# bench_lying_single_arm_dumbbell_tricep_extension,
# single_arm_cable_tricep_extension, suspension_tricep_press, and
# wide_grip_preacher_curl_with_ez_bar,
# single_arm_chest_supported_incline_row preset, JSONL, and manifest files
# running process: 45253 /Applications/Momentum.app/Contents/MacOS/CamiFitApp

git diff --check
# clean / pass
```

### 2026-06-08 Motion Quality Reset

- Paused further exact exercise promotion after reviewing the generated rig
  frames for `bodyweight_jumping_jack`,
  `bench_lying_single_arm_dumbbell_tricep_extension`,
  `single_arm_chest_supported_incline_row`, and
  `machine_chest_supported_row`.
- Generated contact sheets and skeleton-review videos under
  `tmp/motion-review/<exercise_id>/`. The review showed the new dynamic traces
  are hand-authored coordinate sketches, not captured human motion.
- Confirmed with two read-only subagents that the current shipped path for the
  questioned demos is `canonical_archetype_trace` from
  `scripts/motion_reference/compile_archetype_trace.py`, while the intended
  accurate path is MotionReferenceRecorder -> MediaPipe VIDEO raw trace ->
  exercise-specific normalizer -> reviewed `motion_demo_pose` JSONL.
- Improved `scripts/motion_reference/render_mediapipe_trace_review.py` so
  future review frames render `left.*` and `right.*` semantic landmarks, not
  only `primary.*` / `secondary.*`.
- Added finite, timestamp, and normalized-coordinate bounds checks to
  `scripts/motion_reference/audit_motion_coverage.py`. The first pass correctly
  failed the bench-lying tricep and chest-supported row prototype traces because
  foot landmarks sat outside the normalized image frame; the generator math was
  then corrected and those three traces now pass the numeric strict gate while
  remaining synthetic, not guide-ready.
- Added `--require-reference-clips` to the motion coverage audit. This is the
  product-readiness gate for accurate tracking data: it fails until every
  packaged guide trace is backed by an accepted first-party or licensed
  external reference clip.
- Added exact exercise-name targeting to the Swift and Python workout
  generators so a routine request that names any of the 50 golden assessment
  exercises selects that exact exercise when equipment and safety allow it.
- Added app-level evidence coverage so a full-body generated routine surfaces
  all 50 golden exercises in selected or filtered evidence regardless of
  tracking readiness; missing tracking blocks runnable projection, not KG
  recommendation evidence.
- Updated `scripts/motion_reference/audit_kg_motion_readiness.py` so
  `pending_licensed_reference_clip` canonical traces are not guide-ready by
  default. `bodyweight_plank` originally remained a reviewed static exception;
  it is now backed by an accepted external plank clip instead of the canonical
  static trace.
- Updated the app preset list after visible-app review: newly generated dynamic
  prototype presets now appear in a separate `Needs reference clip` section,
  while `Trackable presets` contains only guide-ready app presets. Routine
  generation and coach activation still do not promote synthetic
  reference-capture-required presets as guide-ready routine blocks.
- Preserved `bodyweight_lunge` as the app's protected canonical guide trace.
  The public-domain Wikimedia Commons `Strength Training Circuit- Forward
  Lunge.webm` source
  (<https://commons.wikimedia.org/wiki/File:Strength_Training_Circuit-_Forward_Lunge.webm>,
  public domain as U.S. Army / U.S. federal government work; attribution used:
  Army Combat Fitness Test / U.S. Army via Wikimedia Commons) remains useful as
  extraction-pipeline validation evidence, but it is not an automatic promotion
  target. Lunge is guide-ready in the app because the original canonical trace
  is already ideal; lunge-family KG exercises can use it as the golden
  comparator for future extraction work.
- Made `scripts/motion_reference/export_mediapipe_reference_trace.py`
  profile-aware so new captures write profile metadata, raw review commands, and
  the correct normalizer command when a capture-derived normalizer exists. It no
  longer tells squat, push-up, or future captures to run the lunge normalizer.
- Shifted the source policy from first-party-only to accepted reference clips:
  first-party captures remain valid, but licensed external workout clips are
  also valid when source URL, license, attribution, raw MediaPipe trace,
  normalizer, and review artifacts are preserved. Added
  `--require-reference-clips` as the current product-readiness gate.
- Located and ingested the licensed Wikimedia Commons clip
  `Jumping jack movimiento.ogg` for `bodyweight_jumping_jack`
  (<https://commons.wikimedia.org/wiki/File:Jumping_jack_movimiento.ogg>,
  CC BY-SA 3.0, attribution Albaparejadelrio / Wikimedia Commons). MediaPipe
  extraction produced 96 raw pose frames with 33 landmarks per frame, then
  `scripts/motion_reference/normalize_jumping_jack_trace.py` normalized frames
  0..18 into a 19-frame closed-open-closed guide trace.
- Diagnosed the user-visible stale-app state: `/Applications/Momentum.app` and
  the then-current `dist/Momentum.app` still contained the old 14-frame
  `canonical_archetype_trace` jumping-jack resource, so the open app correctly
  showed `Prototype trace - capture needed` before rebuild/reinstall.
- Rebuilt `dist/Momentum.app`, refreshed `/Applications/Momentum.app` and
  `/Applications/Future Coach.app` from it at 2026-06-08 20:18:13 CDT, and
  relaunched `/Applications/Momentum.app`. The installed bundle now contains the
  19-frame `licensed_external_reference_trace` jumping-jack manifest and the
  visible app shows `Bodyweight Jumping Jack` under `Trackable presets` with a
  green check.
- Current readiness report:

```bash
python3 scripts/motion_reference/audit_kg_motion_readiness.py --summary-only \
  --write-report scripts/motion_reference/kg_motion_readiness.assessment.v0.json
# app_presets=15 app_guide_ready=5
# generated kg_exercises=50 guide_ready=1 archetype_demo_only=23
# recommend_only=26 mapped_incomplete=10 generated_missing=0

python3 scripts/motion_reference/audit_motion_coverage.py --strict
# presets=15 profiles=15 pending_reference_captures=10 failures=0

python3 scripts/motion_reference/audit_motion_coverage.py --strict \
  --require-reference-clips
# expected fail until the remaining exercise clips are located and normalized:
# pending/reference-source failures=10

swift test --disable-sandbox --filter AssignmentExerciseCatalogTests \
  --filter AssignmentWorkoutPlannerTests/testSyntheticReferenceCaptureRequiredExercisesStayRecommendationsOnly \
  --filter AssignmentWorkoutPlannerTests/testFullBodyRoutineEvidenceCoversEveryGoldenExerciseRegardlessOfTrackingReadiness \
  --filter AppExerciseSessionViewModelTests/testDefaultViewModelDiscoversPackagedPresetResources \
  --filter AppExerciseSessionViewModelTests/testLoadsBundledPresetListAndSelectsSquatAndPlank
# selected Swift tests passed

swift test --disable-sandbox --filter WorkoutGeneratorTests
# exact assessment exercise prompts target all 50 golden exercises

(cd kg-canonical && uv run python -m pytest tests/test_workout_generator.py -q)
# exact assessment exercise prompts select all 50 golden exercises

swift test --disable-sandbox
# 326 tests passed

(cd kg-canonical && uv run python -m pytest)
# 156 passed

python3 -m py_compile \
  scripts/motion_reference/audit_motion_coverage.py \
  scripts/motion_reference/audit_kg_motion_readiness.py \
  scripts/motion_reference/render_mediapipe_trace_review.py
# pass

codesign --verify --deep --strict --verbose=2 /Applications/Momentum.app
# /Applications/Momentum.app: valid on disk
# /Applications/Momentum.app: satisfies its Designated Requirement

pgrep -fl "/Applications/Momentum.app/Contents/MacOS/CamiFitApp"
# 60789 /Applications/Momentum.app/Contents/MacOS/CamiFitApp

swift test --disable-sandbox --filter AppExerciseSessionViewModelTests
# 9 tests passed; bundled preset discovery now lists all fifteen packaged
# presets, with three guide-ready presets and pending-capture prototype traces
# separated by tracking readiness.

swift test --disable-sandbox --filter AssignmentWorkoutPlannerTests
# 9 tests passed; full-body evidence still covers all golden exercises while
# synthetic reference-capture-required presets stay recommendation-only for
# routine projection.

./script/build_and_run.sh --verify
# rebuilt and verified dist/Momentum.app after splitting the sidebar sections.

installed bundle refresh/resource check
# /Applications/Momentum.app and /Applications/Future Coach.app refreshed
# 2026-06-08 19:41:06 CDT /Applications/Momentum.app
# running process: 86947 /Applications/Momentum.app/Contents/MacOS/CamiFitApp
# visual app check: Trackable presets shows the three guide-ready app presets;
# Needs reference clip shows synthetic pending-reference presets separately.

2026-06-08 19:54 CDT validation after lunge source-quality reset
# historical receipt before the 20:10 licensed jumping-jack clip ingest
# swift test --disable-sandbox
# 328 tests passed
# swift test --disable-sandbox --filter AssignmentExerciseCatalogTests
# 5 tests passed; assessment status counts are guide_ready=0,
# archetype_demo_only=18, recommend_only=32.
# swift test --disable-sandbox --filter AssignmentWorkoutPlannerTests
# 9 tests passed; lunge-family rows stay recommendation-only until the lunge
# archetype has accepted reference-clip capture.
# swift test --disable-sandbox --filter CoachExerciseActionTests
# 6 tests passed; bodyweight_lunge chat activation fails closed.
# python3 scripts/motion_reference/audit_kg_motion_readiness.py --summary-only
# app_presets=15 app_guide_ready=3
# generated kg_exercises=50 guide_ready=0 archetype_demo_only=18
# recommend_only=32 mapped_incomplete=16 generated_missing=0
# python3 scripts/motion_reference/audit_motion_coverage.py --strict
# presets=15 profiles=15 pending_reference_captures=12 failures=0
# python3 scripts/motion_reference/audit_motion_coverage.py --strict --require-reference-clips
# expected failure remained before jumping-jack ingest: 13 source-quality failures.
# 2026-06-08 19:57 CDT installed app visual check
# running process: 43071 /Applications/Momentum.app/Contents/MacOS/CamiFitApp
# Trackable presets shows only Bodyweight Plank, Bodyweight Push-up, and
# Bodyweight Squat; Bodyweight Lunge and the synthetic traces are in
# Needs reference clip.
# python3 scripts/motion_reference/export_mediapipe_reference_trace.py --exercise-id bodyweight_pushup ...
# smoke passed; manifest emits raw review plus normalize_pushup_trace.py.
# python3 scripts/motion_reference/export_mediapipe_reference_trace.py --exercise-id bodyweight_jumping_jack ...
# smoke passed; manifest emits raw review plus normalize_jumping_jack_trace.py.

2026-06-08 20:10 CDT validation after licensed jumping-jack clip ingest
# downloaded Wikimedia Commons Jumping jack movimiento.ogg
# source: https://commons.wikimedia.org/wiki/File:Jumping_jack_movimiento.ogg
# license: CC BY-SA 3.0; attribution: Albaparejadelrio / Wikimedia Commons.
# MediaPipe export produced 96 raw frames; normalizer selected frames 0..18.
# bundled bodyweight_jumping_jack guide trace is 19 motion_demo_pose frames.
# swift test --disable-sandbox --filter MediaPipePoseProviderTests/testBundledCanonicalMotionDemoTracesDecodeAndReplayThroughEngine --filter JumpingJackAcceptanceTests
# 2 tests passed; bundled jumping-jack trace replays through the engine and
# counts one rep.
# swift test --disable-sandbox --filter AppExerciseSessionViewModelTests --filter AssignmentExerciseCatalogTests --filter CoachExerciseActionTests --filter CodexAppServerClientTests
# 29 tests passed; jumping jack is guide-ready, lunge still fails closed, and
# chat instructions include bodyweight_jumping_jack.
# python3 scripts/motion_reference/audit_kg_motion_readiness.py --summary-only
# app_presets=15 app_guide_ready=4
# generated kg_exercises=50 guide_ready=1 archetype_demo_only=18
# recommend_only=31 mapped_incomplete=15 generated_missing=0
# python3 scripts/motion_reference/audit_motion_coverage.py --strict
# presets=15 profiles=15 pending_reference_captures=11 failures=0
# python3 scripts/motion_reference/audit_motion_coverage.py --strict --require-reference-clips
# expected failure remains: 12 presets still need accepted reference clips.

2026-06-08 20:18 CDT installed-app refresh after user stale-bundle screenshot
# ./script/build_and_run.sh --verify
# rebuilt and verified dist/Momentum.app.
# /Applications/Momentum.app and /Applications/Future Coach.app refreshed from
# dist/Momentum.app at 2026-06-08 20:18:13 CDT.
# installed manifest:
#   source_kind=licensed_external_reference_trace
#   source_page=https://commons.wikimedia.org/wiki/File:Jumping_jack_movimiento.ogg
#   frames=19
# codesign --verify --deep --strict --verbose=2 /Applications/Momentum.app
# /Applications/Momentum.app: valid on disk
# /Applications/Momentum.app: satisfies its Designated Requirement
# running process: 3623 /Applications/Momentum.app/Contents/MacOS/CamiFitApp
# visual app check: Trackable presets shows Bodyweight Jumping Jack,
# Bodyweight Plank, Bodyweight Push-up, and Bodyweight Squat; Needs reference
# clip shows lunge plus the remaining unguided dynamic presets.

2026-06-08 20:31 CDT validation after lunge raw-preserved Commons ingest
# Superseded on 2026-06-09: the raw-preserved Commons trace is retained as
# extractor validation evidence only. The shipped lunge trace was restored to
# the protected canonical lunge guide and must not be overwritten by this
# candidate without an explicit side-by-side product decision.
# source: https://commons.wikimedia.org/wiki/File:Strength_Training_Circuit-_Forward_Lunge.webm
# direct media: https://upload.wikimedia.org/wikipedia/commons/5/57/Strength_Training_Circuit-_Forward_Lunge.webm
# license: Public domain, U.S. Army / U.S. federal government work.
# normalized selected 30..36s side-view segment with --retarget raw
# --fit-viewport and descent-mirror frames 40..84.
# validation candidate is 89 motion_demo_pose frames with
# source_kind=licensed_external_reference_trace.
# python3 scripts/motion_reference/audit_motion_coverage.py --strict --require-reference-clips
# expected failure remains: 11 presets still need accepted reference clips.
# python3 scripts/motion_reference/audit_kg_motion_readiness.py --summary-only
# app_presets=15 app_guide_ready=5
# generated kg_exercises=50 guide_ready=1 archetype_demo_only=23
# recommend_only=26 mapped_incomplete=10 generated_missing=0
# swift test --disable-sandbox --filter MediaPipePoseProviderTests/testBundledBodyweightLungeMotionDemoTraceDecodesAndCountsOneRep --filter LungeAcceptanceTests --filter MotionDemoTimelineTests/testLungeDemoTimelineKeepsFeetPlantedAndCountsOneRep
# 3 tests passed; bundled lunge trace counts one rep and keeps planted
# contacts/loop boundaries stable.
# swift test --disable-sandbox --filter AppExerciseSessionViewModelTests --filter AssignmentExerciseCatalogTests --filter CoachExerciseActionTests --filter CodexAppServerClientTests
# 29 tests passed; lunge is guide-ready and pike still fails closed.
# swift test --disable-sandbox --filter AssignmentWorkoutPlannerTests
# 9 tests passed; lower-body routine projection can include guide-ready lunge
# while wrist-loaded plank/pike remain filtered.

2026-06-08 20:36 CDT installed-app refresh after lunge promotion
# ./script/build_and_run.sh --verify
# rebuilt and verified dist/Momentum.app.
# /Applications/Momentum.app and /Applications/Future Coach.app refreshed from
# dist/Momentum.app, then /Applications/Momentum.app relaunched with
# CAMIFIT_REPO_ROOT=/Users/kelly/Developer/camifit-app.
# installed lunge manifest:
#   source_kind=licensed_external_reference_trace
#   source_page=https://commons.wikimedia.org/wiki/File:Strength_Training_Circuit-_Forward_Lunge.webm
#   frames=89
# installed jumping-jack manifest:
#   source_kind=licensed_external_reference_trace
#   source_page=https://commons.wikimedia.org/wiki/File:Jumping_jack_movimiento.ogg
#   frames=19
# codesign --verify --deep --strict --verbose=2 /Applications/Momentum.app
# /Applications/Momentum.app: valid on disk
# /Applications/Momentum.app: satisfies its Designated Requirement
# running process: 45424 /Applications/Momentum.app/Contents/MacOS/CamiFitApp
# visual app check: Trackable presets shows Bodyweight Jumping Jack,
# Bodyweight Lunge, Bodyweight Plank, Bodyweight Push-up, and Bodyweight Squat;
# Needs reference clip starts with bench/pike and the remaining unguided
# dynamic presets.

2026-06-08 20:47 CDT validation after plank external-clip promotion
# rejected first reviewed Pexels plank candidate 6437916 because MediaPipe
# lower-leg landmarks left the normalized image bounds.
# source: https://www.pexels.com/video/a-woman-doing-plank-exercise-on-a-yoga-mat-7801720/
# direct media: https://videos.pexels.com/video-files/7801720/7801720-uhd_2732_1154_25fps.mp4
# license: Pexels License; attribution used: Pexels / video 7801720.
# selected 0..6s forearm-plank window at 10 fps; raw extraction produced
# 60 MediaPipe frames and review videos under
# dist/motion-reference/bodyweight_plank/pexels_plank_7801720_0_6/raw_review.
# scripts/motion_reference/normalize_plank_trace.py writes a 31-frame
# static-median external-reference hold trace with locked forearm/toe contacts.
# python3 scripts/motion_reference/audit_motion_coverage.py --strict --require-reference-clips
# expected failure remains: 10 presets still need accepted reference clips.
# python3 scripts/motion_reference/audit_kg_motion_readiness.py --summary-only
# app_presets=15 app_guide_ready=5
# generated kg_exercises=50 guide_ready=1 archetype_demo_only=23
# recommend_only=26 mapped_incomplete=10 generated_missing=0
# swift test --disable-sandbox --filter MediaPipePoseProviderTests/testBundledCanonicalMotionDemoTracesDecodeAndReplayThroughEngine --filter PlankAcceptanceTests
# 2 tests passed; bundled plank trace reaches the hold target and all packaged
# demo traces still decode/replay.

2026-06-08 20:50 CDT installed-app refresh after plank reference promotion
# ./script/build_and_run.sh --verify
# rebuilt and verified dist/Momentum.app.
# /Applications/Momentum.app and /Applications/Future Coach.app refreshed from
# dist/Momentum.app, then /Applications/Momentum.app relaunched with
# CAMIFIT_REPO_ROOT=/Users/kelly/Developer/camifit-app.
# installed plank manifest:
#   source_kind=licensed_external_reference_trace
#   source_page=https://www.pexels.com/video/a-woman-doing-plank-exercise-on-a-yoga-mat-7801720/
#   source_license=Pexels License
#   frame_count=31
# running process: 77600 /Applications/Momentum.app/Contents/MacOS/CamiFitApp
# codesign --verify --deep --strict --verbose=2 /Applications/Momentum.app
# /Applications/Momentum.app: valid on disk
# /Applications/Momentum.app: satisfies its Designated Requirement
# visual app check: Trackable presets still shows Bodyweight Jumping Jack,
# Bodyweight Lunge, Bodyweight Plank, Bodyweight Push-up, and Bodyweight Squat;
# Needs reference clip still contains the remaining 10 accepted-reference
# blockers.
```

### 2026-06-09 Launch/Camera Runtime Follow-Up

- Reworked first-open launch behavior so the Momentum onboarding tour presents on
  a fresh app launch before the camera pipeline can stall the first render.
- The app now requests macOS Camera permission from the content bootstrap on
  normal launches, after the onboarding presentation state is set. Guide/synthetic
  launch modes still skip that first-open camera request.
- Added `LiveCameraController.requestPermissionIfNeeded()` and
  `LiveSession.requestCameraPermissionOnLaunch()` so `.notDetermined` status
  transitions through a visible permission request instead of surfacing only as a
  stale denied state.
- Camera mode now owns a standalone live camera session even when no routine
  block is active; guide mode still stops the live camera, and routine camera
  phases still route frames through the routine-owned callback path.
- Hid the normal Record control unless
  `CAMIFIT_SHOW_RECORDING_CONTROLS=1`, keeping the developer capture affordance
  out of the default app surface.
- Installed-app visual check: after resetting Camera TCC plus onboarding
  defaults and running `./script/build_and_run.sh --verify`,
  `/Applications/Momentum.app` opened with the onboarding tour visible and the
  macOS `"Momentum" would like to access the Camera` prompt on top within the
  first captured second. Screenshot evidence:
  `/tmp/camifit_first_launch_onboarding_immediate_20260609.png`.
- Validation:

```bash
swift test --disable-sandbox --filter 'OnboardingFlowTests|PoseOverlayViewTests|CoachExerciseActionTests|RoutineRunnerTests'
# 26 tests passed

swift test --disable-sandbox
# 378 tests passed

tccutil reset Camera com.camifit.app
defaults delete com.camifit.app camifit.onboarding.completed
defaults delete com.camifit.app camifit.onboarding.completedVersion
defaults delete CamiFitApp camifit.onboarding.completed
defaults delete CamiFitApp camifit.onboarding.completedVersion
./script/build_and_run.sh --verify
# rebuilt, signed, installed, and launched /Applications/Momentum.app
```

Accurate motion-data path from here:

- Locate an accepted workout/reference clip per exact exercise. Licensed
  external clips are preferred for the remaining unguided presets; local
  first-party captures remain valid when needed for a missing variant.
- Export MediaPipe VIDEO landmarks with
  `scripts/motion_reference/export_mediapipe_reference_trace.py`.
- Normalize per exercise so semantic landmarks, loop boundaries, contact policy,
  and side labels are explicit in `motion_demo_pose` JSONL.
- Render contact sheets/review video and pass numeric QA before flipping the
  manifest to `trainer_reference_trace` and restoring `guide_ready`.

### 2026-06-09 Rejected-Source Ledger Hardening

- Added a fail-closed rejected-source review gate for accepted licensed
  external motion references. The audit now requires either structured
  `rejected_candidates` entries with source/license/attribution/decision/reason
  or a `rejected_sources` promotion-review record with scope and reason.
- Mirrored the same requirement in `MotionDemoManifest.isGuideEligible`, so a
  bundled licensed external guide can no longer appear in the live Trackable
  app path when the manifest lacks rejected-source review evidence.
- Populated the current accepted external guide records:
  `bodyweight_plank` now structures the rejected Pexels 6437916 plank candidate;
  `single_arm_cable_tricep_extension` carries its rejected Pexels/wger
  candidate ledger in the manifest; `single_arm_dumbbell_preacher_curl` and
  `suspension_tricep_press` explicitly record that no alternate rejected
  source-candidate records were retained during their promotion slice.
- Extended focused Python audit tests so missing rejected-source documentation,
  malformed candidate decisions, valid candidate ledgers, and explicit
  none-retained review records are covered.

Validation evidence:

```bash
python3 -m py_compile \
  scripts/motion_reference/audit_motion_coverage.py \
  scripts/motion_reference/test_audit_motion_coverage.py
# pass

python3 scripts/motion_reference/test_audit_motion_coverage.py
# 8 tests passed

python3 scripts/motion_reference/audit_motion_coverage.py --strict \
  --require-trackable-reference-clips
# presets=14 profiles=15 pending_reference_captures=5 failures=0

python3 scripts/motion_reference/audit_kg_motion_readiness.py --summary-only
# app_presets=14 app_guide_ready=7
# generated kg_exercises=50 guide_ready=3 archetype_demo_only=23
# recommend_only=24 mapped_incomplete=7

swift test --disable-sandbox \
  --filter AvatarHumanoidGLBAssetTests/testMotionDemoManifestFailsClosedWhenMissingOrUnaccepted \
  --filter AvatarHumanoidGLBAssetTests/testGuideReadyGateMatchesPlayableBundleAndAcceptedManifests
# 2 selected tests passed

./script/build_and_run.sh --verify
# built, signed, verified, and installed /Applications/Momentum.app

installed bundle resource check
# running process: /Applications/Momentum.app/Contents/MacOS/CamiFitApp
# installed playable JSONL count=7:
# bodyweight_lunge, bodyweight_plank, bodyweight_pushup, bodyweight_squat,
# single_arm_cable_tricep_extension, single_arm_dumbbell_preacher_curl,
# suspension_tricep_press
# accepted external manifests carry rejected-source ledgers:
# bodyweight_plank rejected_candidates=1
# single_arm_cable_tricep_extension rejected_candidates=2
# single_arm_dumbbell_preacher_curl rejected_sources=none_retained_for_promotion_review
# suspension_tricep_press rejected_sources=none_retained_for_promotion_review

screencapture -x /tmp/camifit_rejected_source_gate_relaunch.png
# visible app check: Trackable presets shows seven trusted guides; guide-less
# Pike/bench-style exercises remain in the assessment catalog, not Trackable.
```

### 2026-06-09 Runnable Routine Projection Hardening

- Tightened assignment exercise coverage so exact or node-property preset
  mappings can only become `guide_ready` when the mapped preset is present in
  `AppExerciseTrackingGate.guideReadyPresetIDs`. Explicit graph properties that
  point at reference-capture-required presets now remain recommendation-only.
- Tightened generated routine projection so only exact `guide_ready` coverage
  becomes executable preset blocks. `archetype_demo_only` coverage still appears
  as recommendation/catalog evidence, but it no longer rides on a trusted app
  preset as a runnable substitute for the exact KG exercise.
- Preserved the original Bodyweight Lunge guide as a trusted lower-body
  priority alongside squat when no lower-body safety constraint blocks the
  routine, while keeping lunge-family archetype variants catalog-only unless
  the exact `Exercise:bodyweight_lunge` is selected or prioritized.

Validation evidence:

```bash
swift test --disable-sandbox \
  --filter AssignmentExerciseCatalogTests \
  --filter AssignmentWorkoutPlannerTests
# 25 selected tests passed

python3 scripts/motion_reference/audit_motion_coverage.py --strict \
  --require-trackable-reference-clips
# presets=14 profiles=15 pending_reference_captures=5 failures=0

python3 scripts/motion_reference/test_audit_motion_coverage.py
# 8 tests passed
```

### 2026-06-09 Protected Lunge Hash Hardening

- Promoted the Bodyweight Lunge golden hash from Swift-test-only protection to
  the reusable Python motion-reference audit. `bodyweight_lunge` is now pinned
  as a protected golden comparator to
  `04920c88fe91d6bd1c0c218bc8ae04477006bc97a6a1111e458d134f9f3a8a65`.
- The strict audit rejects a manifest that points `golden_trace` at the
  source-preserving Commons candidate, even if the mutable `artifact_integrity`
  entries are updated to match that candidate. This keeps extracted motion as
  validation evidence unless an explicit side-by-side product decision changes
  the approved golden.
- Wired `scripts/motion_reference/test_audit_motion_coverage.py` and motion
  audit py-compile checks into `scripts/run_monorepo_gates.sh`, so the standard
  monorepo gate now exercises the rejected-source ledger and protected-lunge
  hash regressions before running strict motion coverage.

Validation evidence:

```bash
python3 -m py_compile \
  scripts/motion_reference/audit_motion_coverage.py \
  scripts/motion_reference/test_audit_motion_coverage.py
# pass

python3 scripts/motion_reference/test_audit_motion_coverage.py
# 8 tests passed, including candidate-as-golden rejection

python3 scripts/motion_reference/audit_motion_coverage.py --strict \
  --require-trackable-reference-clips
# presets=14 profiles=15 pending_reference_captures=5 failures=0

bash -n scripts/run_monorepo_gates.sh
# pass
```

### Item Status

- Item 1 - Python gates: complete.
- Item 2 - Full assessment graph: complete through explicit assignment-mode
  artifact; seed graph remains documented as the small developer fixture.
- Item 3 - KGKit workout app wiring: complete.
- Item 4 - Provenance and alternatives UI: complete through the chat plan-card
  presentation model and tests.
- Item 5 - Assignment Copilot surface: complete for required graph-backed quick
  prompts, fact cards, chart points, and chat routing; richer dashboard polish
  remains future product work.
- Item 6 - Motion-data context: reset in progress. Readiness report support is
  present, `bodyweight_lunge` is restored/protected as the golden comparator,
  Jumping Jack is hard-quarantined, Pike is blocked by visual-rig failure, and
  Trackable presets now include only the seven guide-ready exercises proven by
  replay/audit gates. Remaining exact dynamic guide promotion is blocked
  pending accepted reference clips and visual QA.
- Item 7 - Resolver coverage: complete.
- Item 8 - Ontology/provenance docs: complete.
- Item 9 - End-to-end assignment examples: complete in `kg-canonical/README.md`
  and summarized in the root README.
- Item 10 - Submission README: complete through the root README closeout section
  plus the deeper `kg-canonical/README.md` assignment README.
- Item 11 - Final gates: reopened. Swift focused tests pass, strict motion
  coverage passes with `--require-trackable-reference-clips`, KG readiness
  reports 7 guide-ready app presets, and the installed app launches without the
  Documents-folder prompt after a TCC reset. Full-repo gates remain open because
  the broader worktree is dirty and this goal is still an active motion-quality
  hardening lane.

### 1. Make Python Gates Reliable

Update monorepo scripts and README commands from:

```bash
uv run pytest
```

to:

```bash
uv run python -m pytest
```

Acceptance:

- `scripts/run_monorepo_gates.sh` no longer depends on the `pytest` console
  script.
- `kg-canonical/README.md` and root README commands match the working invocation.
- `uv run python -m pytest` passes from `kg-canonical/`.

### 2. Promote The Full Assessment Graph

Make the Swift runtime consume the full generated assessment graph, or introduce
an explicit assignment-mode artifact that the app and tests use for the
assignment demo.

Acceptance:

- The app/KGKit assignment path can evaluate all 50 golden exercises.
- The artifact source clearly records the golden source hashes and generated
  graph version.
- Tests prove the Swift runtime can load and reason over the generated
  50-exercise graph.
- The old seed graph is either removed from the submission path or clearly
  documented as a small developer fixture only.

### 3. Wire KGKit Workout Generation Into The App

Coach workout requests should call `KGKit.WorkoutGenerator.generateWorkout(...)`
instead of asking the LLM to freehand routines.

Acceptance:

- A coach prompt plus time window produces a `WorkoutPlan` from KGKit.
- Member constraints from the local KG overlay affect generation.
- The generated workout is converted into a runnable `WorkoutRoutine` or other
  app-native plan artifact without letting the LLM decide eligibility.
- The existing authoring gate in `CodexAppServerClient.exerciseAuthoringEnabled`
  remains closed to freeform `ExerciseProgram` generation.

### 4. Render Provenance And Alternatives

Expose the KG decision evidence in the app UI for generated plans.

Acceptance:

- Generated plans show selected exercises.
- Filtered exercises show reason codes and graph paths.
- Limited-equipment and injury cases show safe alternatives.
- The UI makes it clear which decisions were graph-derived.
- Tests cover the presentation model, not just raw KGKit structs.

### 5. Build The Assignment Copilot Surface

Bring KG-backed member context into the app: brief, adherence, sleep, churn risk,
message pattern, quick prompts, and charts.

Acceptance:

- The app can show the morning brief for Jordan.
- Quick prompts cover at least: brief, adherence trend, sleep this week, changed
  since last week, message pattern, and churn risk.
- Chart data is generated from graph facts, not invented prose.
- Missing data returns a no-supporting-fact state.
- The coach chat can summarize fact cards without inventing member facts.

### 6. Preserve The Motion-Data Pipeline Context

The assignment closeout overlaps with avatar guide readiness because graph
exercises are not automatically displayable or measurable. The latest motion
pipeline is documented in:

- `docs/design/2026-06-06-scalable-motion-reference-pipeline.md`
- `docs/design/2026-06-06-bodyweight-lunge-reference-pipeline.md`
- `docs/design/2026-06-05-avatar-guide-motion-demo.md`
- `scripts/motion_reference/README.md`
- `scripts/motion_reference/exercise_motion_profiles.json`

Core rule: the motion spec does not go into MediaPipe. MediaPipe receives images
or video and emits landmarks. Our product transform is:

```text
exercise preset
  -> motion profile
  -> accepted workout/reference clip
  -> MediaPipe VIDEO trace
  -> exercise normalizer / retargeter
  -> contact and phase QA
  -> app MotionDemos JSONL
  -> engine replay test, numeric quality audit, and viewer review
```

Raw MediaPipe landmarks are extraction/debug data, not final guide motion. They
do not encode product semantics such as `primary.knee`, `secondary.knee`,
front/support leg, loop boundaries, planted-foot policy, stable side-view
retargeting, or contact locks. The app should consume compiled
`motion_demo_pose` JSONL under `Sources/CamiFitApp/Resources/MotionDemos`.

Ideal shipped source:

- controlled licensed workout/reference video;
- full body visible, fixed camera, stable lighting;
- exact exercise variant matching the app preset;
- clean top-bottom-top or hold window;
- MediaPipe Pose Landmarker run in deterministic `VIDEO` mode;
- normalizer retargets to canonical side-view landmarks and writes a manifest.

The rig-frame review showed that dynamic canonical archetype traces are not
good enough for product guide motion. They can remain deterministic development
fixtures, but they must not be treated as exact `guide_ready` support until a
captured reference clip or stricter kinematic generator passes visual QA.

Use a fail-closed readiness model:

1. **Trainer reference trace** - preferred for shipped avatar guide motion.
2. **Reviewed static/archetype exception** - allowed only for already-reviewed
   low-risk static or foundational guides such as plank; dynamic exercise
   promotion needs explicit review evidence.
3. **Procedural fallback** - useful only for internal iteration; do not present
   it as authoritative exercise instruction.
4. **Recommend-only KG exercise** - safe to include in KG workout reasoning, but
   not guide/measurement-ready until it maps to a packaged app preset with a
   motion profile and valid demo trace.

Current packaged motion coverage:

- `bodyweight_squat`: first-party/canonical trainer-reference trace exists.
- `bodyweight_lunge`: protected canonical lunge guide remains bundled and
  guide-ready; the public-domain Wikimedia Commons U.S. Army lunge clip is
  MediaPipe-extracted as a raw-preserved validation candidate for comparing
  future extraction output against this ideal example.
- `bodyweight_pushup`: first-party/canonical trainer-reference trace exists.
- `bodyweight_plank`: licensed Pexels forearm-plank clip is
  MediaPipe-extracted, normalized as a static-median external-reference hold,
  reviewed numerically, and promoted to the accepted-reference gate.
- `bodyweight_jumping_jack`: hard-quarantined after live viewer rejection. No
  app preset, playable JSONL, or manifest is bundled; the rejected capture work
  remains source/audit history only.
- `bodyweight_pike`: blocked after visual-rig review failed at the high-hip
  frame. The preset and manifest remain metadata only, with no shipped playable
  JSONL and no Trackable/runnable status.
- The remaining generated dynamic traces (`standing_miniband_hip_flexion`,
  `resistance_band_reverse_curl`, preacher-curl variants, tricep-extension variants,
  suspension press, and chest-supported-row variants) are retained as prototype
  artifacts only. They are visible under `Needs reference clip` and are not
  `guide_ready` until accepted reference clips plus visual QA replace the
  synthetic coordinate sketches.

Superseded pike promotion validation:

- Promoted `bodyweight_pike` from a canonical archetype trace to a licensed
  Pexels external reference trace using
  `scripts/motion_reference/normalize_pike_trace.py`.
- Source: `https://www.pexels.com/video/yoga-flow-in-urban-loft-with-natural-light-31794279/`
  segment 0.8s-3.2s; downloaded media URL
  `https://videos.pexels.com/video-files/31794279/13544679_2560_1440_24fps.mp4`.
- Packaged manifest summary: 59 frames, pike angle 177.68 to 48.99 degrees,
  knee minimum 158.6 degrees, elbow minimum 167.21 degrees, shoulder-stack
  maximum 35.15 degrees.
- `swift test --disable-sandbox --filter
  MediaPipePoseProviderTests/testBundledCanonicalMotionDemoTracesDecodeAndReplayThroughEngine
  --filter AssignmentExerciseCatalogTests --filter
  AppExerciseSessionViewModelTests` passed; bundled pike resource counted one
  rep at 4648ms.
- `python3 scripts/motion_reference/audit_motion_coverage.py --strict
  --require-reference-clips` now fails only for 9 pending licensed-reference
  exercises: `bench_lying_single_arm_dumbbell_tricep_extension`,
  `machine_chest_supported_row`, `resistance_band_reverse_curl`,
  `single_arm_cable_tricep_extension`,
  `single_arm_chest_supported_incline_row`,
  `single_arm_dumbbell_preacher_curl`,
  `standing_miniband_hip_flexion`, `suspension_tricep_press`, and
  `wide_grip_preacher_curl_with_ez_bar`.
- KG motion readiness now reports app presets 15, app guide-ready 6, generated
  graph guide-ready 2, archetype-demo-only 23, recommend-only 25, and
  mapped-incomplete 9.

Superseded pike avatar-retarget validation:

- Visible app review showed the pike guide was using an upright torso head rule
  through the high-hip section, which made the GLB avatar neck/head read
  incorrectly even though the accepted pike landmarks and rep counting were
  valid.
- Updated `Sources/CamiFitApp/AvatarDemoStageView.swift` so horizontal and
  inverted/weight-bearing torso axes use the raw head attachment path, while
  upright exercises keep the torso-anchored head rule.
- Added regression coverage in
  `Tests/CamiFitAppTests/AvatarHumanoidGLBAssetTests.swift` proving the bundled
  pike high-hip frame is classified as inverted/raw-head attachment and the
  bundled squat frame remains upright/torso-anchored.
- Verification:
  `swift test --disable-sandbox --filter AvatarHumanoidGLBAssetTests --filter
  BodyweightPikeAcceptanceTests --filter
  MediaPipePoseProviderTests/testBundledCanonicalMotionDemoTracesDecodeAndReplayThroughEngine`
  passed 6 tests, 0 failures.
- Rebuilt with `./script/build_and_run.sh --verify`, copied the signed
  `dist/Momentum.app` bundle over `/Applications/Momentum.app` and
  `/Applications/Future Coach.app`, and relaunched Momentum with
  `CAMIFIT_GUIDE_EXERCISE=bodyweight_pike`. Pinned high-hip review screenshot:
  `/tmp/camifit-pike-headfix-highhip-final.png`.

### 2026-06-09 Fail-Closed Correction

- Superseded the 2026-06-08 Jumping-Jack replacement promotion after the user
  rejected the live animation. `bodyweight_jumping_jack` is no longer bundled
  as an app preset or playable MotionDemo; it remains only as an extra
  motion-reference profile/audit record.
- Superseded the pike promotion after installed-app frame review showed the
  high-hip rig failure. `bodyweight_pike` remains visible only as
  Recommend only/reference-capture metadata, with no packaged playable JSONL.
- Restored Bodyweight Lunge as the protected comparator instead of letting the
  89-frame Commons extraction replace it. The shipped guide is the earlier
  107-frame guide plus one duplicate frame-0 loop-closure frame. The manifest
  records `protected_golden_source_commit=ce65f61`,
  `acceptance_status=protected_golden_loop_closed`, and the base pre-repair
  trace hash.
- Added a Swift hash guard for the lunge shipped guide:
  `AvatarHumanoidGLBAssetTests/testBodyweightLungeGoldenReferenceHashIsPinned`.
  It pins
  `04920c88fe91d6bd1c0c218bc8ae04477006bc97a6a1111e458d134f9f3a8a65`,
  verifies 108 frames, and asserts any existing
  `dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36/bodyweight_lunge.jsonl`
  candidate is not byte-identical to the app golden.
- Removed the packaged-app default `CAMIFIT_REPO_ROOT` launch environment from
  `script/build_and_run.sh`. Local bundles still write
  `CamiFitRepoRoot.txt` for development, but installed smoke verification now
  tests the same no-default-env launch shape the user gets from
  `/Applications/Momentum.app`.
- Hardened packaged-app resource discovery so `.app` launches do not probe
  `FileManager.default.currentDirectoryPath` for preset, recorded-run, mock
  worker, or live worker discovery. This removes the Documents-folder privacy
  prompt that blocked screenshot/video review.

Validation evidence:

```bash
swift test --disable-sandbox --filter AppExerciseSessionViewModelTests
# 11 tests passed; packaged preset candidates do not include launch current dir.

swift test --disable-sandbox --filter AppRecordedRunCatalogTests
# 5 tests passed; packaged recorded-run candidates do not include launch current dir.

swift test --disable-sandbox --filter AppMockWorkerCommandTests
# 4 tests passed; packaged default worker path resolves under Contents/Resources.

swift test --disable-sandbox --filter LiveWorkerPathsTests
# 12 tests passed; installed app without bundled worker does not use launch current dir.

swift test --disable-sandbox --filter \
  AvatarHumanoidGLBAssetTests/testBodyweightLungeGoldenReferenceHashIsPinned \
  --filter AvatarHumanoidGLBAssetTests/testPikeVisualRigFailureDoesNotShipPlayableMotionDemo \
  --filter MediaPipePoseProviderTests/testGuideReadyMotionDemoTracesDecodeAndReplayThroughEngine
# 3 tests passed; lunge frames=108, final_reps=1, loop/contact delta=0.

python3 scripts/motion_reference/audit_motion_coverage.py --strict \
  --require-trackable-reference-clips
# presets=14 profiles=15 pending_reference_captures=5 failures=0
# bodyweight_lunge frames=108 contact_delta=0.000000 loop_delta=0.000000
# bodyweight_pike demo=missing normalizer=blocked_visual_rig_review_failed
# bodyweight_jumping_jack preset=missing profile=extra

python3 scripts/motion_reference/audit_kg_motion_readiness.py --summary-only
# app_presets=14 app_guide_ready=8
# generated kg_exercises=50 guide_ready=4 archetype_demo_only=23
# recommend_only=23 mapped_incomplete=6 generated_missing=0

tccutil reset SystemPolicyDocumentsFolder com.camifit.app
./script/build_and_run.sh --verify
# installed /Applications/Momentum.app and launched without default
# CAMIFIT_REPO_ROOT environment injection.

/usr/sbin/screencapture -x /tmp/camifit_no_documents_prompt_after_reset.png
# live screenshot showed no Documents permission prompt after TCC reset.
```

For broader assignment/KG coverage, do not plan to source a separate guide clip
for all 50 exercises immediately. Instead:

- map KG exercises to a small set of app presets and motion archetypes;
- classify each KG exercise as `guide_ready`, `archetype_demo_only`,
  `recommend_only`, or `filtered`;
- use canonical archetype traces only as development fixtures or explicit
  archetype-demo evidence, not exact guide motion;
- reserve guide-ready app support for exercises with accepted clip provenance,
  extracted motion data, a normalizer, and replay/review evidence;
- use public/external datasets only when license, camera view, skeleton format,
  and retargeting quality are reviewed and recorded in the manifest.

Motion acceptance checks:

- profile exists for the preset exercise id;
- required landmarks are present in the compiled JSONL;
- declared contact landmarks remain locked or within tolerance;
- first and last loop frames match closely enough to avoid visible jitter;
- rep or hold replay succeeds through the same engine preset;
- visual review confirms the movement reads as the intended exercise;
- for lunges specifically, reject if feet slide/lift, knees bend backward, the
  torso collapses, or the movement reads as a leg swap instead of a stationary
  lunge.

Assignment implication: workout generation can reason over all 50 golden
exercises, but the visible "show me how" and live measurement surface should only
claim support for exercises that satisfy this motion-readiness contract.

### 7. Improve Resolver Coverage

Add fuzzy/local typo tolerance and confidence-aware behavior where it is safe to
do so.

Acceptance:

- Exact and alias behavior remains deterministic.
- Safety-critical unknowns still fail closed or ask clarification.
- Fuzzy matches include confidence and source method metadata.
- Tests cover typo/equivalent phrases for knee, barbell, dumbbell, kettlebell,
  deadlift-family exclusion, lower back, and pec/chest intent.
- No resolver fallback can relax a hard medical or equipment block.

### 8. Tighten Ontology And Provenance Documentation

Document the ontology choices as an intentional subset rather than accidental
absence.

Acceptance:

- README explains how OPE, COPPER, SNOMED CT, SKOS, and PROV-O are used or
  deliberately deferred.
- `MAPS_TO` remains audit metadata, not a safety traversal edge.
- The unverified ontology lock is described honestly.
- The production path for RDF/SKOS/PROV-O/SHACL and pinned ontology releases is
  clear.

### 9. Add End-To-End Assignment Examples

Create submission-ready examples for the required scenarios.

Acceptance:

- Example 1: injury case, such as lower body with left-knee concern.
- Example 2: limited-equipment case, such as dumbbells and kettlebell only.
- Example 3: optional chest/pec isolation or full-body request.
- Each example includes generated workout sections, filtered exercises,
  alternatives, and provenance/filter trace.

### 10. Finish The Submission README

Make the root README defend the project as a staff-engineer take-home.

Acceptance:

- Architecture diagram.
- Stack rationale and tradeoffs.
- How to run locally, ideally with one reliable command.
- How AI was used.
- Production evaluation plan.
- Failure modes and safety monitoring.
- Example inputs and outputs.
- Clear note that all data is synthetic.

### 11. Run Final Gates

Final verification should include:

```bash
cd kg-canonical
uv run python -m pytest
uv run python -m kg.validation
uv run python -m kg.assessment_import

cd ..
swift test --disable-sandbox --filter KGKitTests
swift test --disable-sandbox
scripts/motion_reference/audit_motion_coverage.py --strict
scripts/motion_reference/audit_kg_motion_readiness.py --summary-only
git diff --check
```

If `scripts/run_monorepo_gates.sh` is fixed, use it as the final one-command
gate.

## Priority Order

1. Fix gate command reliability.
2. Promote or expose the full 50-exercise graph in the Swift/app path.
3. Wire KGKit workout generation into the app.
4. Render provenance and alternatives.
5. Add KG-backed copilot member-context surface.
6. Preserve motion-readiness tiers for guide/demo support.
7. Update docs and examples.
8. Run full gates and prepare final push.

## 2026-06-08 Jumping-Jack Viewer Recheck

- User-visible review failed `bodyweight_jumping_jack` after the global
  fixed-frame launch issue was removed.
- Root cause: the packaged trace is not preserved workout motion. The
  normalizer used `Jumping jack movimiento.ogg` only as a scalar phase driver
  and then retargeted onto `jumping_jack_landmarks(factor)`.
- Source/contact-sheet review showed the clip includes unrelated arm-raise
  poses after the jumping-jack frames, and raw MediaPipe skeleton frames contain
  crossed/ambiguous skinny-body frames.
- Demoted `bodyweight_jumping_jack` from guide-ready / chat-activatable status
  to reference-capture-required until a replacement front-view clip and
  non-scalar normalizer pass viewer review.
- Hard-quarantined the rejected app path by making reference-capture-required
  presets non-selectable/non-loadable as runnable programs, excluding
  `Exercise:jumping_jack` from generated workout candidates, removing the
  packaged `bodyweight_jumping_jack` preset, and removing the rejected
  MotionDemos JSONL/manifest from the app bundle.
- Kept the rejected trace metadata only in motion-reference audit docs, and
  hardened avatar stance-centering to prefer bilateral left/right feet when
  only one `primary` side exists.
- Focused verification passed:
  `AvatarHumanoidGLBAssetTests`,
  `AppExerciseSessionViewModelTests/testDefaultViewModelDiscoversPackagedPresetResources`,
  and
  `AssignmentExerciseCatalogTests/testJumpingJackRequiresReferenceRecaptureAfterViewerReviewFailure`.
- At this demotion step, strict coverage failed closed with 10 pending reference
  captures, including `bodyweight_jumping_jack`; the hard-quarantine update
  below removes the rejected preset from the packaged app surface.

## 2026-06-08 Jumping-Jack Hard Quarantine

- Deleted the packaged app preset and MotionDemos bundle artifacts for
  `bodyweight_jumping_jack`; direct activation remains fail-closed through the
  reference-capture-required guard.
- Hardened preset discovery against stale local/user files by hiding
  `bodyweight_jumping_jack` even when an older JSON preset remains in a
  candidate preset directory; direct selection/program loading still fails
  closed as reference-capture-required.
- Removed the canned `jumpingJackFrames` procedural fallback and the
  jumping-jack acceptance test that blessed the rejected synthetic rig.
- Added a KG workout-generation quarantine for `Exercise:jumping_jack`; generic
  full-body requests now cover the 49 non-quarantined assessment exercises, and
  exact jumping-jack prompts return no workout candidates.
- Updated KG motion readiness so `Exercise:jumping_jack` reports
  `audit_status=quarantined`, `mapped_preset_id=null`, and
  `measurement_support=none`.
- Focused verification passed 63 tests across session selection, coach actions,
  assignment catalog/planner, KG workout generation, avatar normalization,
  motion demo timelines, and MediaPipe replay.
- Strict motion coverage now fails closed with 14 packaged presets, 5
  guide-ready presets, 9 pending reference captures, and
  `bodyweight_jumping_jack` only as an extra motion-reference profile.
- Rebuilt, reinstalled, and relaunched `/Applications/Momentum.app`; the visible
  Exercises sidebar shows no `Bodyweight Jumping Jack` row in either
  Trackable presets or Needs reference clip.

## 2026-06-08 Jumping-Jack Replacement Promotion (Superseded)

- Promoted a replacement `bodyweight_jumping_jack` trace from Pexels video
  6326725 after raw rig review selected the right-subject crop:
  `dist/motion-reference/bodyweight_jumping_jack/pexels_6326725/men_jumping_jacks_gym_6326725_right_subject.mp4`.
- Replaced the old scalar-retarget normalizer with a raw-preserving front-view
  normalizer. The accepted trace uses source frames `44..55..68`, preserving a
  real closed-open-closed-follow-through cycle from the MediaPipe body rig.
- Folded in the independent review findings before promotion: included closed
  follow-through frames so the rep machine has a real up phase, moved loop
  closure before viewport fitting, dropped avatar-irrelevant MediaPipe
  finger/face dots from the motion-demo output, and added a foot-confidence QA
  threshold (`foot_min_visibility=0.7068`).
- Added an avatar fit cap for tall overhead guides and a regression test so the
  jumping-jack guide stays inside avatar bounds without changing the underlying
  trace data.
- Restored `bodyweight_jumping_jack` as a packaged app preset and exact KG
  mapping for `Exercise:jumping_jack`; removed the KG/app quarantine for that
  exercise only. Other pending synthetic/reference-capture exercises remain
  non-guide-ready.
- Focused verification passed 33 tests across app preset discovery/selection,
  assignment catalog/planner coverage, avatar bounds, and bundled MediaPipe
  replay; the bundled `bodyweight_jumping_jack` trace is 25 frames and counts
  exactly one rep at `1909ms`.
- Motion audits now report `bodyweight_jumping_jack` as guide-ready. Strict
  motion coverage still fails closed only for the eight remaining
  pending-licensed-reference-clip exercises; KG readiness reports
  `app_guide_ready=7` and generated graph coverage as `guide_ready=3`,
  `archetype_demo_only=23`, `recommend_only=24`, `mapped_incomplete=8`.

## 2026-06-08 Reverse-Curl Candidate Rejection

- Reviewed Pexels video 6326763
  (`men-working-out-together-using-a-resistance-band`) as a candidate external
  source for `resistance_band_reverse_curl`.
- Kept the exercise in reference-capture-required status. The clip is a
  resistance-band curl, but reverse curl correctness depends on pronated grip,
  and the reviewed side/crop angles do not prove that grip clearly enough.
- Raw MediaPipe review rejected both tested crops:
  `dist/motion-reference/resistance_band_reverse_curl/pexels_6326763/extract_18000_23500/raw_review_sheet.jpg`
  and
  `dist/motion-reference/resistance_band_reverse_curl/pexels_6326763/extract_wide_18000_23500/raw_review_sheet.jpg`.
- The normal crop isolates the subject better but leaves the visible working
  arm low-confidence at flexion. The wide crop preserves slightly more hand
  context but still has out-of-bounds wrist frames on the stable side and adds
  partner-hand intrusion risk.
- Promotion decision: rejected. Promoting this capture would create a generic
  elbow-flexion guide, not accurate reverse-curl motion data.

## 2026-06-08 Suspension Tricep Press Promotion

- Promoted `suspension_tricep_press` from synthetic archetype / reference
  capture required to licensed external reference data.
- Source: Pexels video 8435987,
  `https://www.pexels.com/video/a-woman-doing-push-up-8435987/`.
  Direct media resolved to
  `https://videos.pexels.com/video-files/8435987/8435987-hd_1920_1080_25fps.mp4`.
- Selected the 4.5s-10.0s side-view suspension-trainer segment. Raw MediaPipe
  extraction produced 66 frames; the camera-side left arm stayed high
  confidence while the body line remained stable.
- Added `scripts/motion_reference/normalize_suspension_tricep_press_trace.py`
  to preserve the raw side-view landmarks, fit them into the app viewport, and
  mirror the clean flexed-to-extended half-cycle into a closed
  flexed-extended-flexed guide loop.
- Packaged
  `Sources/CamiFitApp/Resources/MotionDemos/suspension_tricep_press.jsonl`
  now contains 83 external-reference frames with elbow range
  `43.0..176.93` degrees and body-line range `165.34..172.47` degrees.
- Updated profile/readiness metadata so `Exercise:suspension_tricep_press`
  maps as exact guide-ready instead of `pending_licensed_reference_clip`.
- Subagent search also checked `standing_miniband_hip_flexion` and
  `bench_lying_single_arm_dumbbell_tricep_extension`. The hip-flexion hits were
  high-knee/knee-drive surrogates without a miniband, and the bench-lying
  triceps hits were paid/restricted or synthetic; none were promoted.
- Focused verification passed 29 Swift tests covering app preset readiness,
  assignment catalog/planner projection, bundled motion-demo replay,
  suspension-triceps timeline behavior, and the suspension-triceps acceptance
  test.
- Strict motion coverage now fails closed with 8 remaining pending reference
  captures; `suspension_tricep_press` reports
  `capture=licensed_external_reference_clip`, `frames=83`, `bounds=ok`, and
  `loop_delta=0.000000`.
- KG motion readiness now reports `app_guide_ready=6`; generated assessment
  graph readiness reports `guide_ready=2`, `recommend_only=25`, and
  `mapped_incomplete=8`.
- Rebuilt, reinstalled, and relaunched `/Applications/Momentum.app`; installed
  bundle manifest for `suspension_tricep_press` reports
  `source_kind=licensed_external_reference_trace`, `frames=83`, and the Pexels
  source page above. Visual app check
  `tmp/current-ui/momentum-after-suspension-tricep-promotion.png` shows
  `Suspension Tricep Press` under Trackable presets and absent from Needs
  reference clip.

## 2026-06-08 Jumping-Jack App Surface Finalization

- Fixed the app default/selection surface so guide-ready exercises open in the
  packaged avatar guide by default instead of the empty live-camera placeholder.
  The camera path remains opt-in through the Camera / Live Camera controls.
- Rebuilt, reinstalled, and relaunched both `/Applications/Momentum.app` and
  `/Applications/Future Coach.app` from `dist/Momentum.app`; both installed
  bundles contain `bodyweight_jumping_jack` preset, JSONL trace, and manifest.
- Visual app check
  `tmp/current-ui/momentum-final-jumping-jack-guide.png` shows
  `Bodyweight Jumping Jack` in Trackable presets with the avatar guide visible,
  not `No pose data yet`.
- Two 0.8s-apart hero-stage screenshots changed by 17,390 cropped pixels,
  confirming the Jumping Jack guide animation advances in the running app.
- Tightened `script/build_and_run.sh --verify` so the packaged app must contain
  the `bodyweight_jumping_jack` preset and MotionDemos files; updated the README
  guide-ready demo list to include jumping jack, pike, and suspension tricep
  press.
- Final focused verification passed 34 Swift tests covering packaged preset
  discovery, Jumping Jack avatar bounds, coach activation/fail-closed behavior,
  Codex supported exercise IDs, and workout generation. KG readiness reports
  `bodyweight_jumping_jack status=guide_ready` and `app_guide_ready=7`.

## 2026-06-09 Jumping-Jack Rig Quality Fix

- User-visible review rejected both the packaged Pexels 6326725 Jumping Jack
  guide and the first Pexels 7299359 replacement. The 6326725 trace moved, but
  the closed frames collapsed the feet into a skinny rig, the torso/arms looked
  rubbery, and the manifest showed a forced endpoint correction of `0.305178`.
  The initial 7299359 replacement improved loop closure but still shipped a
  mirrored `0..6` half-cycle with repeated closed frames, visible limb-length
  drift, and weak head/neck rig readability.
- Reviewed the current bundle and two new subagent reports. Dalton flagged the
  mirrored fragment, duplicate closed tail, bone-length drift, collapsed feet,
  and missing head/neck gate. Hilbert independently recommended keeping
  7299359 only as the timing/phase source and using anatomical retargeting from
  a later source cycle. The coverage audit still fails any manifest whose
  pre-correction loop endpoint delta exceeds `0.08`; the new avatar regression
  also rejects mirrored jumping-jack guide status, duplicate adjacent frames,
  crossed feet, large limb-length drift, and head-center drift.
- Extracted and reviewed Pexels 7299359
  (`https://www.pexels.com/video/elderly-man-doing-jumping-jacks-outside-7299359/`),
  a single-subject front-view jumping-jack clip by Kindel Media under the
  Pexels License.
- Replaced the bundled Jumping Jack trace with a source-timed anatomical
  retarget from raw source frames `98..105..112` (`8167..9333ms`). The new
  trace uses 7299359 only for the real closed-open-closed timing/phase and
  emits a floor-stable bilateral front-view avatar rig instead of raw MediaPipe
  limb geometry. It does not mirror the return and does not pad duplicate
  closed frames. The packaged manifest now reports
  `retarget=source_timed_anatomical_front_view_avatar_rig`,
  `loop_closure=source_timed_anatomical_closed_loop`,
  `max_endpoint_delta_before=0.0`, `max_limb_length_ratio=1.1296`,
  `max_head_center_offset=0.0`, `min_closed_heel_spread=0.06`,
  `max_closed_toe_heel_ratio=2.3333`, `min_open_wrist_y=0.195`, and 15
  unique source-timed frames.
- Ran a second Jumping Jack critic pass after user review still reported
  multiple visible issues. Bernoulli flagged a transient no-count variant,
  stale review artifacts, collapsed/duck-foot closed feet, and residual
  frame-local scaling. Noether independently flagged the silent bundle-fallback
  risk, app-normalizer scale pumping, near/far side asymmetry, glued heels, and
  the review renderer's diagonal nose-to-primary-shoulder skeleton line. The
  accepted trace now keeps the app-normalized shoulder width constant, keeps
  head height constant, uses phase-based toe flare, and counts one rep through
  the bundled engine replay.
- Rendered the new review sheet at
  `dist/motion-reference/bodyweight_jumping_jack/pexels_7299359/extract_0_full/source_timed_anatomical_review_sheet.jpg`.
  The sheet and review videos were refreshed after the stable-floor retarget.
  The sheet shows a readable closed-open-closed jumping-jack rig with
  phase-based feet and no frozen tail. The review renderer still draws a
  simple nose-to-primary-shoulder line; the app rig anchors head/neck from the
  bilateral shoulder center and the centered nose.
- Added and tightened bundled-avatar regression coverage for Jumping Jack
  visible quality: the manifest must be the source-timed anatomical retarget,
  source frames must be unique and monotonic, ankle spread must close and open
  clearly, feet must not cross, head center must stay near the shoulder center,
  adjacent frames must move, closed heels must not collapse, closed toe flare
  must stay bounded, closed knees must not splay wider than the ankles, major
  limb-length drift must stay under `1.20x`, and the app-normalized guide must
  not change avatar shoulder width or pump the head/torso vertically.
- Updated the motion-reference reproduction docs and profile metadata so future
  agents do not re-promote raw-preserved or mirrored jumping-jack traces.
- Focused verification passed Swift tests covering bundled avatar quality and
  bundled engine replay. The new trace counts one rep at `1162ms`:
  `motion-demo-resource-bodyweight_jumping_jack frames=15 final_reps=1
  counted=[1162]`.
- Strict motion coverage now reports `bodyweight_jumping_jack` as
  `demo=ok`, `frames=15`, `capture=licensed_external_reference_clip`, and
  `loop_delta=0.000000`; the only strict failures remain the eight pending
  licensed-reference exercises.
- Rebuilt, reinstalled, and relaunched `/Applications/Momentum.app` and
  `/Applications/Future Coach.app` after the anatomical retarget. Both
  installed bundles contain the 15-frame `98..105..112` anatomical manifest.
  Live screenshots
  `tmp/current-ui/momentum-jj-anatomical-frame-a.png` and
  `tmp/current-ui/momentum-jj-anatomical-frame-b.png` show
  `/Applications/Momentum.app` with `bodyweight_jumping_jack` selected and the
  avatar moving between open and closing phases; ImageMagick reports 37,084
  changed pixels across the screenshots.
- Rebuilt and reinstalled both `/Applications` bundles again after the
  stable-floor Jumping Jack pass. The installed `bodyweight_jumping_jack.jsonl`
  SHA-256 matches the source bundle resource
  (`bbd3cd26cdc1092e8da983b898f3f51cd2fd05b571d56bfbc0370552253ecd79`), and
  the installed manifest reports `min_closed_heel_spread=0.06`,
  `max_closed_toe_heel_ratio=2.3333`, `min_open_wrist_y=0.195`, and
  `max_limb_length_ratio=1.1296`. This automation session could not produce a
  trustworthy fresh live screenshot: shell-launched `/Applications/Momentum.app`
  reported repeated SceneKit/CoreVideo `invalid display count (0)` display-link
  errors and AppleScript did not expose a frontmost normal window. Treat the
  installed bundle hash plus Swift app-normalizer regression tests as the
  current verification evidence until a user-visible GUI screenshot is taken
  from the real display session.

## 2026-06-09 Jumping-Jack Source-Shape Fix

- User review still rejected the guide as visually wrong. A third critic pass
  found that the bundle JSONL was stale relative to the new normalizer and that
  the source-timed retarget still did not follow the source shape: at the apex
  it put the wrists far outside the shoulders (`wrist_spread / shoulder_width`
  about `3.28`) even though source frame `105` has the hands overhead near the
  head (`0.66`).
- Updated `scripts/motion_reference/normalize_jumping_jack_trace.py` so the
  anatomical retarget keeps the real `98..105..112` closed-open-closed source
  timing but drives the wrists along a jumping-jack arc: outward through the
  transition, then inward overhead at the apex. Added a hard
  `max_open_wrist_spread_ratio` gate so starfish-style open frames cannot be
  promoted again.
- Regenerated and repackaged
  `Sources/CamiFitApp/Resources/MotionDemos/bodyweight_jumping_jack.jsonl`.
  The new manifest reports `max_open_wrist_spread_ratio=0.6364`,
  `min_open_wrist_y=0.205`, `min_closed_heel_spread=0.07`,
  `max_closed_toe_heel_ratio=1.7143`, `max_limb_length_ratio=1.1296`, and
  15 unique source-timed frames.
- Fixed `scripts/motion_reference/render_mediapipe_trace_review.py` so review
  frames draw either left/right landmarks or primary/secondary aliases, not
  both. The refreshed sheet at
  `dist/motion-reference/bodyweight_jumping_jack/pexels_7299359/extract_0_full/source_timed_anatomical_review_sheet.jpg`
  now shows hands overhead near the head instead of the previous starfish apex.
- Fixed app playback/rendering artifacts that could make corrected data look
  wrong: bundled timelines now skip the artificial closed-pose hold when first
  and last frames already match, and the GLB lower-leg retargeter now clamps
  only pathological lower-leg proportions instead of moving normal Jumping Jack
  knees.
- Focused verification passed the Jumping Jack avatar-quality tests, the new
  no-closed-hold timeline test, and bundled replay. Engine replay still counts
  one rep:
  `motion-demo-resource-bodyweight_jumping_jack frames=15 final_reps=1
  counted=[1162]`.
- Strict motion coverage still reports `bodyweight_jumping_jack` as
  `demo=ok`, `frames=15`, `capture=licensed_external_reference_clip`, and
  `loop_delta=0.000000`; the only strict failures remain the eight pending
  licensed-reference exercises.
- Rebuilt `dist/Momentum.app`, refreshed `/Applications/Momentum.app` and
  `/Applications/Future Coach.app`, and verified both installed bundles. The
  installed `bodyweight_jumping_jack.jsonl` SHA-256 matches the source bundle
  resource (`7e0b530288fed2ea07123024b627b788063811237558cf67c21b006c3abf5a0b`)
  and both app bundles pass `codesign --verify --deep --strict --verbose=2`.
- Shell-launching `/Applications/Momentum.app` from this Codex session still
  creates a no-window process with SceneKit/CoreVideo `invalid display count
  (0)` errors, so the hidden automation-launched process was killed instead of
  leaving it running. Treat the installed bundle hash, refreshed review sheet,
  and focused Swift tests as current evidence until the app is opened from the
  real GUI session.

## 2026-06-09 Preacher-Curl Reference Promotion

- Promoted `single_arm_dumbbell_preacher_curl` from synthetic
  `pending_licensed_reference_clip` to `licensed_external_reference_trace`
  using the Pixabay clip
  <https://pixabay.com/videos/crossfit-gym-workout-training-66991/> by
  `tixonov_valentin` under the Pixabay Content License. Local source clip:
  `dist/motion-reference/single_arm_dumbbell_preacher_curl/pixabay_66991/crossfit_gym_workout_training_66991.mp4`.
- Used the audited right/camera-side source cycle `41..56..64`
  (`4100..5600..6400ms`). Raw MediaPipe had the correct extended-flexed-extended
  phase (`145.26 -> 24.12 -> 152.24` degrees) and stable endpoints, but the
  wrist/forearm visibly shortened under dumbbell occlusion, so the promoted
  guide keeps source timing and phase while using a stable anatomical retarget.
- Added
  `scripts/motion_reference/normalize_single_arm_dumbbell_preacher_curl_trace.py`.
  The emitted 27-frame guide uses a planted upper arm, constant forearm length,
  a source-shaped quick return, and a short extended settle for the
  EMA-filtered rep counter. Manifest summary now reports
  `source_kind=licensed_external_reference_trace`,
  `retarget=source_timed_anatomical_side_view_avatar_rig`,
  `min_primary_elbow_angle=47.38`, `max_primary_elbow_angle=177.38`,
  `max_upper_arm_tilt=22.62`, `max_forearm_length_ratio=1.0`, and
  `max_endpoint_delta=0.0`.
- Refreshed review artifacts at
  `dist/motion-reference/single_arm_dumbbell_preacher_curl/pixabay_66991/extract_0_24916/external_review/`
  and the full-frame sheet
  `dist/motion-reference/single_arm_dumbbell_preacher_curl/pixabay_66991/extract_0_24916/external_review_sheet.jpg`.
- Removed preacher curl from the app `referenceCaptureRequiredPresetIDs`,
  removed the KG assignment catalog reference-capture override, and added
  `single_arm_dumbbell_preacher_curl` to coach action supported IDs. The
  Exercise tab now classifies it as exact `guide_ready` instead of
  recommendation-only.
- Added packaged provenance coverage in
  `SingleArmDumbbellPreacherCurlAcceptanceTests`, updated app preset discovery
  and assignment catalog counts, and added a planner projection test proving
  `Build an arms preacher curl routine. only dumbbell and preacher curl bench.`
  maps to the runnable `single_arm_dumbbell_preacher_curl` preset.
- Focused verification passed:
  `SingleArmDumbbellPreacherCurlAcceptanceTests`,
  bundled motion-demo replay, assignment catalog tests, app preset discovery,
  preacher-curl planner projection, coach action tests, Codex app-server client
  tests, and `git diff --check`. Bundled replay counts one rep at `2100ms`:
  `motion-demo-resource-single_arm_dumbbell_preacher_curl frames=27 final_reps=1 counted=[2100]`.
- Motion coverage without the licensed-reference requirement passes with
  `presets=15`, `profiles=15`, `pending_reference_captures=7`, and
  `failures=0`. The stricter `--require-reference-clips` gate now fails only
  the seven remaining pending licensed-reference exercises:
  `bench_lying_single_arm_dumbbell_tricep_extension`,
  `machine_chest_supported_row`, `resistance_band_reverse_curl`,
  `single_arm_cable_tricep_extension`,
  `single_arm_chest_supported_incline_row`,
  `standing_miniband_hip_flexion`, and
  `wide_grip_preacher_curl_with_ez_bar`.
- KG motion readiness now reports `app_presets=15`, `app_guide_ready=8`, and
  generated assessment coverage as `guide_ready=4`,
  `archetype_demo_only=23`, `recommend_only=23`, `mapped_incomplete=7`.
- Rebuilt `dist/Momentum.app`, refreshed `/Applications/Momentum.app` and
  `/Applications/Future Coach.app`, and verified both installed bundles with
  `codesign --verify --deep --strict --verbose=2`. The installed preacher JSONL
  SHA-256 is
  `ff23a465cec5d47a9a2c824e74d8da38d9b07910e9ed406486696bc515f2d630` in both
  apps and matches the source bundle. `/Applications/Momentum.app` is running
  as process `86318`; this shell did not obtain a reliable window listing from
  System Events, so user-visible GUI confirmation remains the final manual
  check.

## 2026-06-09 Jumping-Jack Source-Shape Repair

- User review still rejected `bodyweight_jumping_jack` as visibly wrong after
  the previous stable-floor retarget. A read-only subagent audit confirmed the
  bundled trace was not stale, but the motion was too synthetic: the old
  normalizer used the source clip only for phase, fixed the head/torso in every
  frame, kept ankle/heel/toe `y` values perfectly flat, and allowed collapsed
  overhead elbow angles.
- Reworked `scripts/motion_reference/normalize_jumping_jack_trace.py` while
  keeping the same licensed Pexels 7299359 source cycle `98..105..112`
  (`8167..9333ms`). The new retarget lowers the head toward the source
  shoulder ratio, adds bounded torso/head bounce, gives the ankles a small
  source-like hop instead of flat rails, delays the arm close-in so elbows no
  longer collapse early, and fixes the closed-pose wrist sign so arms hang
  outside the torso.
- Regenerated and repackaged
  `Sources/CamiFitApp/Resources/MotionDemos/bodyweight_jumping_jack.jsonl`.
  The bundled JSONL SHA-256 now matches the dist source trace at
  `e4dd4f8390664bab1bd2ce94bc1895417a5b68b9837570a6911aabe2e6581a5e`.
  Manifest summary reports `frames=15`, `max_limb_length_ratio=1.1853`,
  `max_open_wrist_spread_ratio=0.7273`, `min_open_wrist_y=0.205`,
  `min_closed_heel_spread=0.07`, and no app frame-local ceiling rescale.
- Refreshed the review sheet at
  `dist/motion-reference/bodyweight_jumping_jack/pexels_7299359/extract_0_full/source_timed_anatomical_review_sheet.jpg`.
  The sheet now shows closed arms outside the body, side-raise transition,
  source-like bent-overhead hands, open stance, and return without the previous
  fixed-head/flat-foot rail artifact.
- Tightened `AvatarHumanoidGLBAssetTests` so Jumping Jack guide quality now
  requires controlled head/torso bounce, constant app-normalized shoulder
  width, bounded foot lift, readable closed feet, no starfish apex, and no
  severe elbow collapse. Focused Jumping Jack avatar tests pass.
- Verification passed:
  `swift test --filter AvatarHumanoidGLBAssetTests/testJumpingJack`,
  `swift test --filter MediaPipePoseProviderTests/testBundledCanonicalMotionDemoTracesDecodeAndReplayThroughEngine`,
  `swift test --filter AppExerciseSessionViewModelTests`,
  `swift test --filter AssignmentExerciseCatalogTests`,
  `python3 scripts/motion_reference/audit_motion_coverage.py --strict`, and
  `python3 scripts/motion_reference/audit_kg_motion_readiness.py --summary-only --write-report scripts/motion_reference/kg_motion_readiness.assessment.v0.json`.
  Bundled replay still counts one Jumping Jack rep at `1162ms`.
- Parallel subagent audits rejected the local machine-row and cable-tricep
  candidates for promotion in this pass. The row candidate is a generic
  seated/band/cable row, not a machine chest-supported row. The cable-tricep
  candidate is exercise-relevant but not preservation-grade, has source-ID
  ambiguity (`5319432` local vs public Pexels `5319433`), and conflicts with the
  current left-side preset contract. Both remain pending licensed-reference
  exercises.
- Rebuilt `dist/Momentum.app` with `./script/build_and_run.sh --package`,
  refreshed `/Applications/Momentum.app` and `/Applications/Future Coach.app`,
  and verified both installed bundles with
  `codesign --verify --deep --strict --verbose=2`. Both installed Jumping Jack
  JSONLs match the source bundle SHA-256
  `e4dd4f8390664bab1bd2ce94bc1895417a5b68b9837570a6911aabe2e6581a5e`.
  `/Applications/Momentum.app` relaunched as process `35088`. A shell
  `screencapture` from this automation session produced an all-black image, so
  live GUI visual confirmation still needs to happen from the real display
  session.

## 2026-06-09 Jumping-Jack App-Visible Repair Follow-Up

- User review still rejected `bodyweight_jumping_jack` as visibly wrong after
  the source-shape repair. A second read-only subagent audit confirmed the old
  tests only proved a 2D skeleton trace and did not prove the actual app-avatar
  path or clean-trace form-cue behavior.
- Reworked `scripts/motion_reference/normalize_jumping_jack_trace.py` again
  while keeping the same licensed Pexels 7299359 source cycle `98..105..112`
  (`8167..9333ms`). The accepted retarget now uses a lower high-V wrist apex,
  reduced stance spread, steadier head/torso motion, and arm geometry that
  avoids both the previous bent goalpost apex and a flat starfish pose.
- Regenerated and repackaged
  `Sources/CamiFitApp/Resources/MotionDemos/bodyweight_jumping_jack.jsonl` and
  manifest. The bundled trace SHA-256 now matches the dist source trace at
  `5e278ccb5d9c5519888f310e7b651cca164f3e1c1fafcf2f7cd18c293265dd0c`.
  Manifest summary reports `frames=15`, `max_limb_length_ratio=1.1491`,
  `max_open_wrist_spread_ratio=2.4091`, `min_open_wrist_y=0.195`,
  `ankle_spread=1.8636` at the open frame, `viewport_fit.scale=1.0`, and
  `loop_closure.max_endpoint_delta_before=0.0`.
- Tuned `bodyweight_jumping_jack` preset thresholds in both root and packaged
  preset resources: `up_when` is now `jack_open < 0.90`, and the arms/feet form
  rules use `>= 1.20` with `min_violation_ms=120`. This keeps the clean guide
  from cueing during normal return frames while still requiring a readable
  overhead/open stance.
- Tightened `AvatarHumanoidGLBAssetTests` again so Jumping Jack now proves
  clean bundled replay counts exactly one rep, emits zero selected form cues,
  reaches an open signal only when both arms and feet are open, keeps open
  wrists in a high-V band, preserves app-normalized shoulder width, and avoids
  severe elbow collapse.
- Verification passed:
  `swift test --filter AvatarHumanoidGLBAssetTests/testJumpingJack`,
  `swift test --filter MediaPipePoseProviderTests/testBundledCanonicalMotionDemoTracesDecodeAndReplayThroughEngine`,
  `swift test --filter AppExerciseSessionViewModelTests`,
  `python3 scripts/motion_reference/audit_motion_coverage.py --strict`,
  `python3 scripts/motion_reference/audit_kg_motion_readiness.py --summary-only --write-report scripts/motion_reference/kg_motion_readiness.assessment.v0.json`,
  JSON validation for the motion profile and Jumping Jack presets, and
  `git diff --check`. Bundled replay now counts one Jumping Jack rep at
  `1079ms` and the clean trace emits no selected form cues.
- The stricter
  `python3 scripts/motion_reference/audit_motion_coverage.py --strict --require-reference-clips`
  gate still fails only the seven remaining pending licensed-reference
  exercises: `bench_lying_single_arm_dumbbell_tricep_extension`,
  `machine_chest_supported_row`, `resistance_band_reverse_curl`,
  `single_arm_cable_tricep_extension`,
  `single_arm_chest_supported_incline_row`,
  `standing_miniband_hip_flexion`, and
  `wide_grip_preacher_curl_with_ez_bar`.
- Parallel read-only subagent audits rejected two local candidate promotions:
  Pexels 6286166 is an upright overhead triceps extension, not
  `bench_lying_single_arm_dumbbell_tricep_extension`; Pexels 6326763 is a
  generic resistance-band curl and does not prove the pronated-grip
  `resistance_band_reverse_curl` semantic. Both remain pending licensed
  external reference clips.
- Rebuilt `dist/Momentum.app` with `./script/build_and_run.sh --package`,
  refreshed `/Applications/Momentum.app` and `/Applications/Future Coach.app`,
  verified both installed bundles with
  `codesign --verify --deep --strict --verbose=2`, and confirmed the installed
  Jumping Jack JSONL SHA-256 matches the source bundle at
  `5e278ccb5d9c5519888f310e7b651cca164f3e1c1fafcf2f7cd18c293265dd0c`.
  Attempting to launch `/Applications/Momentum.app` from this Codex execution
  context started `CamiFitApp`, but SceneKit logged
  `CVDisplayLinkCreateWithCGDisplays error -6661 due to invalid display count (0)`
  and no visible accessibility window was exposed. The headless process was
  stopped; direct user-session visual confirmation remains required.

## 2026-06-09 Jumping-Jack Dense-Retarget Repair

- User review still rejected `bodyweight_jumping_jack` as visibly wrong. The
  current packaged trace was not missing, but visual review showed multiple
  data problems: only 15 frames, a too-wide transition wrist spread, mostly
  sliding feet, a later knee-crossing regression during retarget tuning, and
  an overhead elbow collapse.
- Reworked `scripts/motion_reference/normalize_jumping_jack_trace.py` again
  while keeping the same licensed Pexels 7299359 source cycle `98..105..112`
  (`8167..9333ms`). The accepted repair now upsamples the source-timed cycle to
  29 output frames, restores the source-like side-raise transition before the
  overhead count frame, uses an explicit knee solver with closed-stance
  clamping so the travelling/open legs are not locked straight, keeps foot lift
  bounded, and preserves a clean closed-open-closed loop.
- Regenerated and repackaged
  `Sources/CamiFitApp/Resources/MotionDemos/bodyweight_jumping_jack.jsonl`.
  The bundled JSONL SHA-256 matches the dist source trace at
  `0c4b79ef1878ea989138ad29af2ee9e7dc5f0b7251dcf49c2edf01d293905958`.
  Manifest summary now reports `frames=29`, `upsample_factor=2`,
  `max_limb_length_ratio=1.1821`, `max_open_wrist_spread_ratio=2.0909`,
  `max_wrist_spread_ratio=2.6647`, `min_open_wrist_y=0.198`,
  `max_closed_knee_ankle_ratio=1.6571`, and
  `loop_closure.max_endpoint_delta_before=0.0`.
- Tightened `AvatarHumanoidGLBAssetTests` so Jumping Jack now proves the
  29-frame output/source-frame mapping, monotonic source frame IDs, no crossed
  knees or ankles, smoother adjacent motion, bounded side-raise wrist spread,
  overhead count-frame shape, bent travelling/open knees, bounded foot lift,
  stable full-timeline avatar normalization, no severe elbow collapse, one
  clean rep, and zero selected form cues.
- Focused verification passed:
  `swift test --filter AvatarHumanoidGLBAssetTests/testJumpingJack`. The
  broader bundled replay test also counts `bodyweight_jumping_jack` as one rep
  at `1041ms`, and still counts the repaired
  `machine_chest_supported_row` trace as one rep at `4750ms`.
- Additional validation passed JSON parsing for the Jumping Jack manifest,
  presets, and motion profile, `python3 scripts/motion_reference/audit_motion_coverage.py --strict`
  (`bodyweight_jumping_jack demo=ok frames=29 capture=licensed_external_reference_clip`),
  and scoped `git diff --check`.
- Rebuilt `dist/Momentum.app` with `./script/build_and_run.sh --package`,
  refreshed `/Applications/Momentum.app` and `/Applications/Future Coach.app`,
  and verified both installed bundles with
  `codesign --verify --deep --strict --verbose=2`. Both installed Jumping Jack
  JSONLs match the source bundle SHA-256
  `0c4b79ef1878ea989138ad29af2ee9e7dc5f0b7251dcf49c2edf01d293905958`.
  `/Applications/Momentum.app` launched as process `91641` from this Codex
  context, but `System Events` reported no `CamiFitApp` windows; the no-window
  process was stopped. Final visible confirmation remains the user's live app
  window after opening `/Applications/Momentum.app` normally.

## 2026-06-09 Machine Chest-Supported Row Promotion

**Superseded:** this promotion was later reversed in
`2026-06-09 Source-Provenance / Machine Row License Demotion` because the
Commons source page still marks the imported YouTube file as `License review
needed`. Treat the rows below as historical debugging notes only; current app
truth is preset + manifest metadata only, no packaged Machine Row JSONL, and no
Trackable/runnable Machine Row support until source-license review is resolved.

- Fixed the malformed packaged `machine_chest_supported_row` JSONL. The
  previous external retarget was labeled as raw `type=pose` even though it
  contained normalized `landmarks`; Swift decoded it as MediaPipe worker output
  and failed on missing `poses_detected`. The regenerated trace now emits
  `type=motion_demo_pose` with source frame/timestamp and phase metadata.
- Promoted the Commons/YouTube machine T-bar row source:
  <https://commons.wikimedia.org/wiki/File:How_to_properly_do_Machine_T-Bar_Rows.webm>.
  Current Commons metadata lists Colossus Fitness as author, YouTube as source,
  and CC BY 3.0 licensing, while still marking the imported YouTube license as
  needing Commons review. The app profile and manifest preserve that caveat
  instead of claiming Commons review is complete.
- Reused the accepted `84.0s-91.0s` segment and regenerated
  `Sources/CamiFitApp/Resources/MotionDemos/machine_chest_supported_row.jsonl`
  from
  `scripts/motion_reference/normalize_machine_chest_supported_row_trace.py`.
  The bundled JSONL SHA-256 matches the dist source trace at
  `b757fd0f15928269ecaab2a6f3c7c4927189d0e79d7f457d0c0d2ac359d2a3aa`.
- Updated `exercise_motion_profiles.json`, app preset readiness, and assignment
  catalog mapping so `machine_chest_supported_row` is exact guide-ready instead
  of pending reference capture. The remaining pending licensed-reference set is
  now six exercises: `bench_lying_single_arm_dumbbell_tricep_extension`,
  `resistance_band_reverse_curl`, `single_arm_cable_tricep_extension`,
  `single_arm_chest_supported_incline_row`, `standing_miniband_hip_flexion`,
  and `wide_grip_preacher_curl_with_ez_bar`.
- Verification passed:
  `swift test --filter MachineChestSupportedRowAcceptanceTests` and
  `swift test --filter MediaPipePoseProviderTests/testBundledCanonicalMotionDemoTracesDecodeAndReplayThroughEngine`.
  Bundled replay now reports
  `motion-demo-resource-machine_chest_supported_row frames=84 final_reps=1 counted=[4750]`.
- Added a `row_finish` cue grace adjustment for the machine-row preset:
  `min_violation_ms=1000`. The clean source-timed trace had been producing a
  false `row_finish` cue during the normal return before the `up_when` predicate
  fully settled; the acceptance test now proves the bundled trace counts one rep
  and emits no selected form cues.

## 2026-06-09 Installed App Playback Follow-Up

- Rebuilt `dist/Momentum.app` after the Machine Row promotion and SceneKit
  guide redraw fix, refreshed both `/Applications/Momentum.app` and
  `/Applications/Future Coach.app`, and verified both installed bundles with
  `codesign --verify --deep --strict --verbose=2`.
- Both installed applications contain the corrected bundled traces:
  `bodyweight_jumping_jack.jsonl`
  `0c4b79ef1878ea989138ad29af2ee9e7dc5f0b7251dcf49c2edf01d293905958` and
  `machine_chest_supported_row.jsonl`
  `b757fd0f15928269ecaab2a6f3c7c4927189d0e79d7f457d0c0d2ac359d2a3aa`.
- Changed `AvatarSceneView` so guide motion is driven by SwiftUI timeline
  updates and explicit redraws instead of SceneKit continuous playback. This
  avoids treating SceneKit's display link as the source of truth for guide
  animation.
- Added full-timeline avatar normalization for bundled guide timelines. The
  visible guide no longer recomputes the floor/scale from each individual
  frame, so Jumping Jack preserves visible hop/foot lift instead of visually
  skating on a per-frame floor.
- A Codex-launched `/Applications/Momentum.app` process still reports
  `CVDisplayLinkCreateWithCGDisplays error -6661 due to invalid display count
  (0)` and `System Events` reports zero windows from this execution context, so
  shell-launched live visual verification remains blocked. The installed bundle
  is refreshed; the user's visible app window remains the final truth surface.
- Verification passed after these changes:
  `swift test --filter AvatarHumanoidGLBAssetTests/testJumpingJackBundleTimelineDoesNotHoldDuplicateClosedLoopEndpoint`,
  `swift test --filter AvatarHumanoidGLBAssetTests/testJumpingJackGuideKeepsReadableFeetAndStableLimbLengths`,
  `swift test --filter AvatarHumanoidGLBAssetTests/testJumpingJackTallOverheadFramesStayInsideAvatarGuideBounds`,
  `swift test --filter AppExerciseSessionViewModelTests`,
  `swift test --filter AssignmentExerciseCatalogTests`, and
  `swift test --filter MediaPipePoseProviderTests/testBundledCanonicalMotionDemoTracesDecodeAndReplayThroughEngine`.
- `python3 scripts/motion_reference/audit_kg_motion_readiness.py --summary-only --write-report scripts/motion_reference/kg_motion_readiness.assessment.v0.json`
  now reports `app_presets=15`, `app_guide_ready=9`, generated graph
  `guide_ready=5`, `archetype_demo_only=23`, `recommend_only=22`, and
  `mapped_incomplete=6`.

## 2026-06-09 Pending Reference Clip Audit

- Re-ran the strict licensed-reference gate:
  `python3 scripts/motion_reference/audit_motion_coverage.py --strict --require-reference-clips`.
  It still fails closed for the remaining six pending licensed-reference
  exercises:
  `bench_lying_single_arm_dumbbell_tricep_extension`,
  `resistance_band_reverse_curl`,
  `single_arm_cable_tricep_extension`,
  `single_arm_chest_supported_incline_row`,
  `standing_miniband_hip_flexion`, and
  `wide_grip_preacher_curl_with_ez_bar`.
- Independent read-only subagent source search ranked wger exercise 803 video
  59 as the best next promotion candidate for
  `single_arm_cable_tricep_extension`: CC-BY-SA 4, author `Goulart`, API name
  `One Arm Triceps Extensions on Cable`, full `0.0s-12.28s` repeated cable
  pushdown/extension cycles, and visible working shoulder/elbow/wrist with
  partial hip. Before packaging, fetch/export/review it and verify the preset's
  left/right landmark contract.
- The same search kept wger exercise 465 video 53 as only a re-review lead for
  `wide_grip_preacher_curl_with_ez_bar`, not a promotion. It is CC-BY-SA and
  has preacher support and a curl cycle, but prior local review rejected the
  machine/plate-bar presentation as not exact wide-grip EZ-bar preacher curl.
- Independent read-only subagent audit rejected Pexels 29569378 as
  `bench_lying_single_arm_dumbbell_tricep_extension`. The clip is Pexels
  free-to-use, but the frames show an incline bilateral dumbbell press
  (`0.0s-16.0s`) followed by setup/exit, not a single-arm lying dumbbell
  triceps-extension cycle.
- Independent read-only subagent audit rejected the local cable-triceps Pexels
  candidate. The public match appears to be Pexels 5319433, a cable triceps
  pushdown/extension clip, but the local folder is `pexels_5319432`, the
  manifest has no source metadata, and raw MediaPipe does not preserve the
  preset's `left`-arm contract. The left shoulder/elbow/wrist/hip chain meets
  visibility `>=0.65` in only `25/126` records, and the opposite arm is not
  stable enough to rescue the source.
- Read-only subagent source discovery found no promotable stock/open source for
  `resistance_band_reverse_curl`, `standing_miniband_hip_flexion`, or
  `wide_grip_preacher_curl_with_ez_bar`. The best reverse-curl hit remains
  Pexels 6326763, already rejected as generic band-curl motion with ambiguous
  pronated grip. Hip-flexion hits were no-miniband holds or generic band-leg
  work. The exact wide-grip EZ-bar preacher-curl requirement was not met by the
  searched sources.
- Local review added openly licensed wger candidates as durable rejection
  evidence:
  - wger exercise 465 videos 53 and 54 are CC-BY-SA preacher-curl clips, but
    they show machine/plate or dumbbell/handle preacher curls, not wide-grip
    EZ-bar preacher curls.
  - wger exercise 95 video 50 is CC-BY-SA cable-machine footage, but it is a
    cable biceps curl, not a cable triceps extension.
  - wger exercise 584 is a single-arm preacher curl with a dumbbell and should
    not be routed to either cable-triceps or wide-grip EZ-bar preacher-curl
    promotion.
- Local review kept Pexels 6022753 rejected for
  `machine_chest_supported_row`. The local contact sheet shows an outdoor
  seated resistance-band/cable-style row, with no chest pad and no machine
  chest support.
- Independent read-only subagent search found one conditional machine-row lead:
  Wikimedia Commons `How to properly do Machine T-Bar Rows.webm` appears
  semantically strong for a machine chest-supported T-bar row, with a likely
  clean rep at `84.0s-91.0s` and a backup window at `60.0s-72.5s`. It was not
  promoted because Commons still marks the imported YouTube license as needing
  license review, and the three-quarter/front angle plus pad/machine occlusion
  still need pose review.
- The same subagent found no strict license-usable candidate for
  `single_arm_chest_supported_incline_row`. Exercises.com.au and Trainest were
  semantic near-misses but all-rights-reserved/non-downloadable; the Tenor GIF
  lacked clear permissive provenance; Commons bent-over/T-bar row candidates
  were unsupported rows, not chest-supported incline dumbbell rows.
- Updated `scripts/motion_reference/exercise_motion_profiles.json` with
  concrete rejected-candidate entries for the reviewed Pexels, wger, and
  Wikimedia near-misses. No new guide trace was promoted in this pass.

## 2026-06-09 Jumping-Jack Fail-Closed Demotion

- User-visible review still rejected `bodyweight_jumping_jack` as visibly
  wrong after the dense-retarget repair. The packaged JSONL was not stale:
  `Sources/CamiFitApp/Resources/MotionDemos/bodyweight_jumping_jack.jsonl`
  matched the dist trace and the focused Swift Jumping Jack tests were still
  green, which exposed a bad acceptance gate rather than a packaging miss.
- Local measurement and read-only subagent critique found concrete guide
  failures in the current Pexels 7299359 retarget: raw source frame `105` has
  bent overhead arms, while bundled open frame `14` becomes a straight high-V;
  feet mostly slide laterally; closed knees stay too wide relative to closed
  feet; and wrist/elbow deltas are spiky enough to pop in the app avatar.
- Re-reviewed Pexels 7746545 as a possible replacement. The video framing is
  stronger, but raw MediaPipe arm landmarks remain ambiguous around
  hair/sleeves/background during overhead frames, so it was kept as a visual
  reference only, not promoted.
- Demoted `bodyweight_jumping_jack` from guide-ready to
  `pending_licensed_reference_clip` in the app and KG coverage gates:
  `AppExerciseSessionViewModel.referenceCaptureRequiredPresetIDs` now includes
  it, `AssignmentExerciseCatalog` returns it as recommend-only with
  `pending_licensed_reference_clip`, and coach base instructions no longer list
  it as a supported chat-activatable exercise.
- Updated the motion profile and README so Pexels 7299359 is explicitly a
  rejected forensic artifact. Future promotion must add a source-shape residual
  gate, adjacent wrist/elbow smoothness caps, visible foot-lift scoring, and a
  tighter closed knee/ankle spread gate before Jumping Jack can be guide-ready
  again.
- Verification after demotion passed JSON validation, app preset discovery,
  assignment catalog coverage, coach action fail-closed behavior, the focused
  planner projection regression, strict motion coverage without the reference
  requirement, KG motion-readiness report generation, and `git diff --check`.
  `audit_motion_coverage.py --strict --require-reference-clips` now fails
  closed for six pending exercises, including `bodyweight_jumping_jack`.
  KG readiness reports `app_presets=15`, `app_guide_ready=9`, generated graph
  `guide_ready=5`, `archetype_demo_only=23`, `recommend_only=22`, and
  `mapped_incomplete=6`.
- Rebuilt `dist/Momentum.app` with `./script/build_and_run.sh --package`,
  refreshed `/Applications/Momentum.app` and `/Applications/Future Coach.app`,
  and verified both installed bundles with
  `codesign --verify --deep --strict --verbose=2`. Both installed resource
  bundles still contain the rejected Jumping Jack JSONL for forensic review
  (`0c4b79ef1878ea989138ad29af2ee9e7dc5f0b7251dcf49c2edf01d293905958`),
  but app/catalog readiness now blocks it from guide activation. A shell
  `open -n /Applications/Momentum.app` launch again produced a no-window
  `CamiFitApp` process and an all-black screenshot from this automation
  context, so the process was stopped.

## 2026-06-09 Motion-Quality Gate Hardening

- Re-audited the current motion registry before promoting any more exercises:
  strict coverage still reports 15 packaged presets, 9 app guide-ready presets,
  and 6 pending reference captures:
  `bench_lying_single_arm_dumbbell_tricep_extension`,
  `bodyweight_jumping_jack`, `resistance_band_reverse_curl`,
  `single_arm_chest_supported_incline_row`,
  `standing_miniband_hip_flexion`, and
  `wide_grip_preacher_curl_with_ez_bar`.
- Read-only subagent review confirmed the richest existing source evidence is
  still under `dist/motion-reference/bodyweight_jumping_jack/`, but every tried
  Jumping Jack candidate is rejected or caveated. It ranked
  `resistance_band_reverse_curl` as the next-best existing extraction depth
  because two Pexels 6326763 raw MediaPipe extracts and review sheets already
  exist, while chest-supported incline row and miniband hip flexion have no
  usable dist source directories yet.
- Added executable `quality_gates` for `bodyweight_jumping_jack` in
  `scripts/motion_reference/exercise_motion_profiles.json`: open/transition
  wrist spread bounds, closed knee/ankle anatomy, wrist/elbow smoothness caps,
  minimum ankle vertical travel, and a source-shape residual comparing the
  packaged `source_frame_id=105` frame against the raw MediaPipe source frame.
  These gates are enforced automatically for accepted reference clips and
  reported for pending forensic traces.
- Hardened `scripts/motion_reference/audit_motion_coverage.py` so accepted
  reference clips cannot carry `capture.rejection_reason`, a rejected normalizer
  status, or failing profile quality gates. Normal `--strict` keeps pending
  traces non-blocking but now prints Jumping Jack as `quality=pending_failed`;
  `--enforce-pending-quality-gates` intentionally fails the current rejected
  Jumping Jack trace with the same reasons it failed visual review.
- Wired the same acceptance and quality-gate checks into
  `scripts/motion_reference/audit_kg_motion_readiness.py` so KG/routine guide
  readiness cannot diverge from the motion coverage audit if a pending trace is
  prematurely marked accepted.
- Verification:

```bash
python3 -m json.tool scripts/motion_reference/exercise_motion_profiles.json >/dev/null
# json-ok

python3 scripts/motion_reference/audit_motion_coverage.py --strict
# presets=15 profiles=15 pending_reference_captures=6 failures=0
# bodyweight_jumping_jack ... quality=pending_failed

python3 scripts/motion_reference/audit_motion_coverage.py --strict --enforce-pending-quality-gates
# expected failure: bodyweight_jumping_jack rejected_reference_capture,
# rejected_normalizer_status, open/transition wrist spread, closed knee/ankle,
# wrist/elbow smoothness, ankle vertical travel, and source-shape residual gates

python3 scripts/motion_reference/audit_kg_motion_readiness.py --summary-only
# app_presets=15 app_guide_ready=9
# generated kg_exercises=50 guide_ready=5 archetype_demo_only=23
# recommend_only=22 mapped_incomplete=6
```

## 2026-06-09 Wide-Grip Preacher Source Review

- Re-opened `wide_grip_preacher_curl_with_ez_bar` as a possible next pending
  promotion because wger exercise 465 is openly licensed, has SZ-Bar equipment
  metadata, and its English translation describes placing the EZ curl bar on a
  preacher bench.
- Read-only subagent review recommended keeping wger videos 53 and 54 rejected:
  license was defensible (`license=2`, author `Goulart`; wger license 2 is
  CC-BY-SA 4), but video 53 reads as a plate-loaded/preacher-station variation
  and video 54 as a dumbbell/handle variation rather than a clear wide-grip
  free EZ-bar preacher curl.
- Extracted video 53 anyway to avoid relying only on the contact sheet:

```bash
python3 scripts/motion_reference/export_mediapipe_reference_trace.py \
  --video dist/motion-reference/wide_grip_preacher_curl_with_ez_bar/source_candidates/wger_465_video53/source.mov \
  --exercise-id wide_grip_preacher_curl_with_ez_bar \
  --output-dir dist/motion-reference/wide_grip_preacher_curl_with_ez_bar/wger_465_video53/extract_0_12000 \
  --fps 12 \
  --start-ms 0 \
  --end-ms 12000
# raw_mediapipe.jsonl frames=144

python3 scripts/motion_reference/render_mediapipe_trace_review.py \
  --raw dist/motion-reference/wide_grip_preacher_curl_with_ez_bar/wger_465_video53/extract_0_12000/raw_mediapipe.jsonl \
  --video dist/motion-reference/wide_grip_preacher_curl_with_ez_bar/source_candidates/wger_465_video53/source.mov \
  --output-dir dist/motion-reference/wide_grip_preacher_curl_with_ez_bar/wger_465_video53/extract_0_12000/raw_review \
  --fps 12
```

- Raw review showed MediaPipe can follow the camera-side elbow cycle, but that
  only proves a trackable preacher-curl elbow path. It does not prove the exact
  wide-grip free EZ-bar setup required for this preset. The profile and README
  now include the raw extraction and review-sheet paths as rejection evidence.
- Ran a wider YouTube search with `yt-dlp` for exact wide-grip EZ-bar preacher
  curl videos. Several exact-looking clips were found, but all reported
  `license=NA`, so they were not ingested under the accepted-reference policy.
- No guide-ready promotion was made; the preset remains
  `pending_licensed_reference_clip`.

## 2026-06-09 Jumping Jack Fail-Closed Runtime Gate

- User-visible review still rejected `bodyweight_jumping_jack` as visibly wrong
  in multiple ways. A read-only motion-data subagent audit matched the
  executable quality-gate failures: the bundled retarget has excessive
  open/transition wrist spread, straightens the raw source's bent overhead
  elbows, keeps closed knees too wide relative to the ankles, under-produces
  vertical ankle/foot travel, and still has wrist/elbow frame pops.
- A read-only app-runtime subagent audit found that stale app bundles can
  confuse the visible surface (`dist/Momentum.app` was current while older
  `dist/CamiFitApp.app` and `dist/Future Coach.app` were stale/missing the new
  Jumping Jack resources), but the current resource itself is rejected. The fix
  therefore blocks the rejected trace instead of trying to bless or relaunch it.
- Added `AppExerciseTrackingGate` as the shared runtime list for presets that
  still require accepted reference capture. `AppExerciseSessionViewModel`,
  `MotionDemoBundleStore`, and the guide overlays now use that gate so
  `bodyweight_jumping_jack` cannot load a bundled MotionDemo or fall back to a
  synthetic compiler guide.
- Tagged both the source and packaged Jumping Jack manifests with
  `acceptance_status=rejected_after_user_visual_review`,
  `normalizer_status=rejected_after_user_visual_review`, and an explicit
  `rejection_reason`. The manifest loader now refuses pending/rejected
  manifests.
- Updated `script/build_and_run.sh` so guide-ready presets must package
  MotionDemos, while capture-needed presets only require their preset JSON.
  This prevents the build script from forcing rejected traces into the app.
- Replaced old Jumping Jack avatar tests that blessed the rejected trace with a
  fail-closed regression: the bundled Jumping Jack manifest must be marked
  rejected, and `MotionDemoBundleStore.timeline/guideTimeline` must return nil.

## 2026-06-09 Jumping Jack Playable Trace Removal

- User reported the Jumping Jack animation was still visibly wrong after the
  runtime gate. The remaining risk was that
  `Sources/CamiFitApp/Resources/MotionDemos/bodyweight_jumping_jack.jsonl`
  still existed and could be packaged or reached by stale preview code.
- Removed the playable Jumping Jack JSONL from app resources. The rejected
  Pexels 7299359 output remains only under `dist/motion-reference/...` as
  forensic review evidence, while the bundled manifest preserves the rejection
  metadata.
- Changed the motion registry from `viewer_status=bundled_canonical_trace` to
  `viewer_status=pending_reference_capture` for `bodyweight_jumping_jack`.
  This makes `audit_motion_coverage.py --strict` treat the missing app demo as
  intentional instead of requiring the rejected trace.
- Added a packaging tripwire to `script/build_and_run.sh`: while Jumping Jack is
  capture-required, the build fails if
  `MotionDemos/bodyweight_jumping_jack.jsonl` appears in the packaged app
  bundle.
- Strengthened the avatar regression so the test asserts there is no bundled
  Jumping Jack JSONL and that `MotionDemoBundleStore.timeline/guideTimeline`
  still return nil.
- Rebuilt and copied the verified bundle into both `/Applications/Momentum.app`
  and `/Applications/Future Coach.app`, then relaunched
  `/Applications/Momentum.app`. Final verification showed both Applications
  bundles contain only the rejected manifest and preset for Jumping Jack, with
  no playable `MotionDemos/bodyweight_jumping_jack.jsonl`.

## 2026-06-09 Remaining Pending Source Sweep

- Closed the parallel subagent source sweeps for the remaining pending
  capture-required presets. No new non-first-party clip was promotion-ready.
- `standing_miniband_hip_flexion`: Pexels 8836855 and Pixabay 303828 were weak
  resistance-band leg/band leads, but neither clearly showed the required
  side-view standing miniband hip-flexion motion or enough landmarks for a
  defensible source-preserving extraction.
- `single_arm_chest_supported_incline_row`: wger exercise 1283 is semantically
  close and openly licensed as exercise metadata, but has no video from the
  wger video API; wger 310/1637 also had no usable videos.
- `bench_lying_single_arm_dumbbell_tricep_extension`,
  `resistance_band_reverse_curl`, and
  `wide_grip_preacher_curl_with_ez_bar`: no exact candidate was found. wger 465
  video 53 remains the closest curl-family source, but it still reads as a
  plate-loaded/preacher-station variation rather than a clear wide-grip free
  EZ-bar preacher curl.
- Decision: keep all five non-Jumping-Jack pending presets fail-closed unless a
  future exact licensed clip plus exercise-specific normalizer passes raw
  MediaPipe review, semantic review, and app-visible avatar review.

## 2026-06-09 Jumping Jack Pexels 4764124 Recheck

- A read-only source-search subagent ranked Pexels 4764124 by Gustavo Fring as
  the best remaining licensed visual Jumping Jack candidate. I re-opened the
  local review artifacts before promoting it.
- The source contact sheet is a real front-view jumping jack, but the extracted
  pose trace is not guide-safe: the raw review sheets show floating head/face
  landmarks, unstable lower limbs, and arm/foot phase mismatch.
- Recorded Pexels 4764124 as `rejected_after_pose_review` in
  `scripts/motion_reference/exercise_motion_profiles.json` and kept
  `bodyweight_jumping_jack` capture-gated with no bundled playable JSONL.

## 2026-06-09 Standing Miniband Hip-Flexion Source Triage

- Downloaded four licensed Pexels leg-band candidates into
  `dist/motion-reference/standing_miniband_hip_flexion/source_candidates/` and
  generated contact sheets before attempting any MediaPipe promotion.
- Rejected Pexels 8416674 because it is a tight hand/band/thigh crop without
  enough visible hip/knee/ankle/stance-foot evidence for source-preserving
  extraction.
- Rejected Pexels 8837226 and 8836976 because both show standing miniband
  lateral hip abduction, not the required forward/up knee-drive hip-flexion
  cycle.
- Rejected Pexels 7477907 because it is lying floor leg-band work, not standing
  hip flexion with a planted stance foot.
- Recorded all four candidates in
  `scripts/motion_reference/exercise_motion_profiles.json`; the exercise stays
  `pending_reference_capture` with no bundled playable JSONL.

## 2026-06-09 Jumping Jack App Surfacing Fix

- Tightened app preset discovery so `bodyweight_jumping_jack` and the other
  capture-required presets are excluded from `availablePresets` entirely. They
  still fail closed by ID through `AppExerciseTrackingGate`, but they no longer
  appear as runnable/trackable exercises in the Exercises tab.
- Removed the Exercises-tab `Needs reference clip` preset subsection so
  capture-required placeholders are represented only through the assessment
  catalog as recommendation-only metadata until a licensed source-preserving
  trace is accepted.
- Updated `AppExerciseSessionViewModelTests` to prove the guide-ready picker has
  only the nine accepted playable presets and that explicit activation of
  `bodyweight_jumping_jack` still throws `presetRequiresReferenceCapture`.

## 2026-06-09 Subagent Source Review Results

- Reviewed the read-only subagent findings for
  `bench_lying_single_arm_dumbbell_tricep_extension`,
  `single_arm_chest_supported_incline_row`,
  `wide_grip_preacher_curl_with_ez_bar`, `resistance_band_reverse_curl`, and
  `standing_miniband_hip_flexion`.
- Kept all five capture-gated. The returned Pexels, Pixabay, Commons, and wger
  candidates either had clean licenses but wrong exercise semantics, no attached
  video, multi-person/ambiguous setup, AI-generated source concerns, or weak
  pose extraction suitability.
- No subagent candidate was promoted into bundled app motion data.

## 2026-06-09 Remaining Placeholder Trace Removal

- Extended the Jumping Jack fail-closed rule to the other five
  capture-required presets:
  `bench_lying_single_arm_dumbbell_tricep_extension`,
  `resistance_band_reverse_curl`,
  `single_arm_chest_supported_incline_row`,
  `standing_miniband_hip_flexion`, and
  `wide_grip_preacher_curl_with_ez_bar`.
- Removed their playable 17-frame canonical-archetype JSONLs from
  `Sources/CamiFitApp/Resources/MotionDemos/`, changed their motion profiles
  to `viewer_status=pending_reference_capture`, and changed their manifest
  metadata to `playable_trace_packaged=false`,
  `acceptance_status=pending_reference_capture`, and
  `normalizer_status=pending_source_preserving_normalizer`.
- Generalized `script/build_and_run.sh` so every capture-required preset keeps
  its preset JSON but fails packaging if a playable MotionDemo JSONL is bundled
  before an accepted licensed reference capture exists.
- Updated the guide-avatar regression to assert all six capture-required
  presets have no bundled JSONL and cannot produce `MotionDemoBundleStore`
  timelines.
- Recorded wger exercise 245 video 60 as a rejected near-match for
  `bench_lying_single_arm_dumbbell_tricep_extension`. It is useful
  license-defensible skullcrusher-family evidence, but it is bilateral rather
  than single-arm and the 12.0s-18.7s raw MediaPipe review has arm dropout and
  low-confidence landmarks, so it is not exact or clean enough to promote.
- Also inspected wger exercise 211 video 57 for the same preset. It is
  license-defensible (`CC-BY-SA 4`, author history `Goulart`), but the contact
  sheet shows a seated/incline overhead single-arm dumbbell triceps extension,
  not the requested bench-lying pattern, so it is recorded as rejected without
  extraction.
- While broadening the guide-ready replay regression, found
  `single_arm_cable_tricep_extension` was marked guide-ready but its bundled
  source trace replayed to zero reps. Regenerated the same wger 803 licensed
  source cycle with a longer flexed return (`1250..2000..3250ms`), replacing
  the 22-frame bundle with a 25-frame bundle that replays to one counted rep.

## 2026-06-09 Jumping Jack Source Recheck

- Rechecked the candidate rig frames instead of trying to tune the rejected app
  animation by eye. The current app/resource state remains fail-closed: there
  is no `Sources/CamiFitApp/Resources/MotionDemos/bodyweight_jumping_jack.jsonl`
  and no installed `/Applications/Momentum.app` or
  `/Applications/Future Coach.app` playable Jumping Jack JSONL.
- Regenerated the Pexels 6326725 right-subject crop as raw-preserved
  `rework_upsample2_v2` and `rework_upsample3` candidates. The 3x variant
  fixed the smoothness thresholds (`motion.max_adjacent_delta=0.0344`,
  `motion.max_second_difference=0.0295`) and the trace itself was structurally
  valid (`frames=73`, `loop_delta=0.0`), but it still failed the shape gates:
  `cycle.max_closed_knee_ankle_ratio=2.2898` exceeds `1.35`,
  `cycle.max_open_wrist_spread_ratio=2.7846` exceeds `1.6`, and
  `cycle.max_wrist_spread_ratio=3.9395` exceeds `2.0`.
- Verified and downloaded Pexels 3048954 by Pressmaster
  (`Woman doing jumping jacks near riverside with bridge in view`) after
  checking the live Pexels source and license pages. Extracted the first
  3.5 seconds at 12 fps into
  `dist/motion-reference/bodyweight_jumping_jack/pexels_3048954/extract_0_3500/`.
  Raw review rejected it because the usable portion rotates into side view and
  produces narrow side-view skeletons, floating head landmarks, and unstable
  upper-body/foot confidence.
- Recorded both Pexels 6326725 and Pexels 3048954 as rejected Jumping Jack
  candidates in `scripts/motion_reference/exercise_motion_profiles.json`.
  `bodyweight_jumping_jack` remains `pending_reference_capture`; do not bundle
  it or include it in trackable recommendations until a clean front-view,
  source-preserving reference passes the shape, smoothness, loop, engine replay,
  and app-visible review gates.
- Reviewed the source-search subagent's follow-up candidates. Pexels 7746545
  has the best front-facing Pexels framing, but its only fully confidence-clean
  cycle (`82..88..94`) still fails app-guide gates: closed knee/ankle ratio
  `3.4435 > 1.35`, max wrist spread `3.8081 > 2.0`, max adjacent arm delta
  `0.0793 > 0.055`, max second difference `0.1075 > 0.04`, and left ankle
  vertical travel `0.0213 < 0.025`. It stays rejected.
- Downloaded and extracted Pexels 4767084 by Gustavo Fring. The 4K source
  looks clean to the eye, but MediaPipe does not preserve the leg opening
  (`peak ankle spread ~=0.27..0.60` while the source legs are visibly open),
  so it is rejected after raw pose review.
- Downloaded and extracted Coverr `coverr-jumping-jacks-5469/1080p.mp4`.
  This is the closest raw pose candidate visually and cycle `17..30..47`
  is smooth (`motion.max_adjacent_delta=0.0252`,
  `motion.max_second_difference=0.0122`), but it is not promoted because the
  Coverr license includes dataset/AI-training caveats and because the current
  app-guide shape gates still fail (`cycle.max_open_wrist_spread_ratio=3.5213`
  and `cycle.max_wrist_spread_ratio=4.14`). Treat it as research evidence, not
  packaged app data.

## 2026-06-09 Jumping Jack Hard Quarantine Reapplied

- User review still reports `bodyweight_jumping_jack` as visibly wrong. Do not
  tune the rejected animation forward; the app must not expose it until a clean
  external reference passes source, shape, replay, and visible-review gates.
- Deleted the packaged app preset stub and rejected manifest:
  `Sources/CamiFitApp/Resources/Presets/bodyweight_jumping_jack.json` and
  `Sources/CamiFitApp/Resources/MotionDemos/bodyweight_jumping_jack.manifest.json`.
  Also removed the root development preset stub
  `Presets/bodyweight_jumping_jack.json`.
- Tightened `script/build_and_run.sh` so packaging fails if any Jumping Jack
  app preset, playable JSONL, or manifest is bundled.
- Reapplied KG generator quarantine for `Exercise:jumping_jack` in both Swift
  and Python. Full-body candidate pools now cover the 49 non-quarantined
  assessment exercises, and an exact Jumping Jack prompt returns no runnable
  workout candidate.
- Regenerated `scripts/motion_reference/kg_motion_readiness.assessment.v0.json`;
  current strict motion coverage reports `presets=14`, `app_guide_ready=9`, and
  `bodyweight_jumping_jack preset=missing profile=extra`.
- Built with the debug Momentum verify path, synced `dist/Momentum.app` into
  both `/Applications/Momentum.app` and `/Applications/Future Coach.app`, and
  relaunched `/Applications/Future Coach.app`. A fresh installed-bundle scan
  found no `*jumping*` or `*jack*` files, and the live screen showed Trackable
  presets starting with Lunge/Pike/Plank and no Jumping Jack entry.
- Verification:
  `swift test --filter AvatarHumanoidGLBAssetTests --filter AppExerciseSessionViewModelTests --filter AssignmentExerciseCatalogTests --filter AssignmentWorkoutPlannerTests --filter CoachExerciseActionTests`,
  `swift test --filter WorkoutGeneratorTests`,
  `.venv/bin/python -m pytest tests/test_workout_generator.py` from
  `kg-canonical`, and the strict motion-coverage / KG-motion-readiness audits
  all passed.

## 2026-06-09 Lunge Golden Reference Correction

- User review correctly identified that the original `bodyweight_lunge` guide
  was already the ideal example and should have been used to validate the
  extraction pipeline, not replaced by raw-preserved external motion.
- Restored the shipped lunge JSONL and manifest to the original canonical
  lunge trace: `phase=canonical_lunge_retarget`, `retarget=canonical-lunge`,
  and 89 app-ready `motion_demo_pose` frames.
- Updated `scripts/motion_reference/README.md` so the lunge section now treats
  the Wikimedia Commons raw-preserved trace as a validation candidate only. The
  stale commands that copied the candidate into
  `Sources/CamiFitApp/Resources/MotionDemos/bodyweight_lunge.*` were removed.
- Added `scripts/motion_reference/compare_trace_to_golden.py` to compare any
  candidate JSONL against the protected lunge guide using hip-anchored,
  body-scaled landmark deltas plus primary/secondary knee-angle agreement.
- Recorded the lunge profile role as `protected_golden_comparator`, with the
  shipped canonical trace as `golden_trace`, `capture.status` as
  `protected_golden_reference`, and the Commons raw-preserved trace as
  `candidate_trace` with `candidate_status=licensed_external_reference_clip`.
- Added a lunge-specific guardrail to
  `scripts/motion_reference/normalize_lunge_trace.py`: generated manifests for
  `bodyweight_lunge` now emit a compare-to-golden command by default. A
  copy-into-app command is only generated when
  `--allow-promote-bodyweight-lunge` is passed.
- Updated the older bodyweight-lunge reference design note so it no longer
  instructs agents to place candidate output directly into shipped app
  resources.
- Latest comparison result for the Commons raw-preserved candidate:
  `mean_xy_error_body_scaled=0.3773`,
  `primary_knee_mean_abs_delta_degrees=20.40`,
  `primary_knee_correlation=0.9906`,
  `secondary_knee_mean_abs_delta_degrees=56.60`, and
  `secondary_knee_correlation=0.7074`. This is useful extraction evidence, but
  not a blind replacement for the shipped guide.
- Verification after correction passed:
  `python3 -m py_compile scripts/motion_reference/compare_trace_to_golden.py`,
  `python3 -m json.tool scripts/motion_reference/exercise_motion_profiles.json`,
  `scripts/motion_reference/compare_trace_to_golden.py --golden Sources/CamiFitApp/Resources/MotionDemos/bodyweight_lunge.jsonl --candidate dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36/bodyweight_lunge.raw_preserved.jsonl`,
  `python3 scripts/motion_reference/audit_motion_coverage.py --strict`,
  `python3 scripts/motion_reference/audit_kg_motion_readiness.py --summary-only`,
  and focused Swift lunge tests:
  `swift test --disable-sandbox --filter MediaPipePoseProviderTests/testBundledBodyweightLungeMotionDemoTraceDecodesAndCountsOneRep --filter LungeAcceptanceTests --filter MotionDemoTimelineTests/testLungeDemoTimelineKeepsFeetPlantedAndCountsOneRep`.

## 2026-06-09 Source Search Follow-Up

- `resistance_band_reverse_curl`: source-search subagent found no
  promotion-ready exact clip. Pexels 8401283 is the best next visual-review
  lead because it is real resistance-band footage, but it is not confirmed as
  reverse-curl grip/phase. CDC Commons biceps-curl footage and Pexels dumbbell
  curl footage are useful sanity controls only, not acceptable app references
  for the band reverse-curl preset. Keep the preset fail-closed.
- `standing_miniband_hip_flexion`: source-search subagent found no
  promotion-ready exact clip. Pexels 6326732 is the closest visual lead, but it
  is a tight foot/shin crop without defensible hip/trunk landmarks. Other
  Pexels leads are lateral abduction, quadruped/floor work, or upper-body band
  pulls rather than standing miniband hip flexion. Keep the preset fail-closed.

## 2026-06-09 Generic Fail-Closed Motion Gate Tightening

- Tightened `scripts/motion_reference/audit_motion_coverage.py --strict` so any
  profile with `viewer_status=pending_reference_capture` fails the audit if a
  playable `Sources/CamiFitApp/Resources/MotionDemos/<exercise_id>.jsonl`
  appears. This makes the no-playable-demo rule generic instead of relying only
  on the packaging script's per-preset allow/block list.
- Tightened both `scripts/motion_reference/audit_motion_coverage.py` and
  `scripts/motion_reference/audit_kg_motion_readiness.py` so accepted
  first-party, licensed external, and protected-golden references must preserve
  the expected source chain. The strict motion audit now fails guide-ready
  claims when required manifest/profile metadata or local artifacts are missing:
  source label, source URL/media/license/attribution for external clips,
  raw MediaPipe trace, source video, normalizer script, and generated output
  trace where applicable.
- Accepted references must also declare the QA gates that justify promotion.
  The audits now require a visual-review gate (`viewer_reviewed` or
  `agent_visual_reviewed`) and an engine replay/hold gate
  (`engine_counts_one_rep` or `engine_accepts_hold`). Licensed external traces
  must additionally declare source-pose review (`raw_pose_reviewed` or
  `source_clip_reviewed`).
- Added `AppExerciseSessionViewModelTests/testReferenceCaptureGateMatchesPendingMotionProfiles`
  so bundled pending-reference presets in
  `scripts/motion_reference/exercise_motion_profiles.json` must be present in
  `AppExerciseTrackingGate.referenceCaptureRequiredPresetIDs`, and every
  pending profile must have no playable app MotionDemo JSONL.
- Current resource state:
  app presets = 14, app guide-ready = 9, pending reference captures = 5, and
  `bodyweight_jumping_jack` remains a profile-only rejected/quarantined extra
  with no bundled app preset, JSONL, or manifest.
- Verification after this gate tightening passed:
  `python3 -m py_compile scripts/motion_reference/audit_motion_coverage.py scripts/motion_reference/audit_kg_motion_readiness.py`,
  `python3 scripts/motion_reference/audit_motion_coverage.py --strict`,
  `python3 scripts/motion_reference/audit_kg_motion_readiness.py --summary-only`,
  and focused Swift fail-closed tests:
  `swift test --disable-sandbox --filter AppExerciseSessionViewModelTests/testReferenceCaptureGateMatchesPendingMotionProfiles --filter AppExerciseSessionViewModelTests/testLoadsBundledPresetListAndSelectsGuideReadyPresetsOnly --filter AssignmentExerciseCatalogTests/testLoadsAllAssessmentExercisesForExerciseTab --filter AssignmentWorkoutPlannerTests/testSyntheticReferenceCaptureRequiredExercisesStayRecommendationsOnly --filter AssignmentWorkoutPlannerTests/testRejectedJumpingJackStaysRecommendationOnlyAndDoesNotProjectRoutineBlock`.
- Negative verification also passed: a temporary fake
  `standing_miniband_hip_flexion.jsonl` failed strict motion coverage as a
  forbidden pending-reference playable demo, and a temporary pike manifest with
  a missing source-video artifact made strict motion coverage fail plus KG
  readiness classify `bodyweight_pike` as `not_ready`.
- Additional negative verification removed `viewer_reviewed` from temporary
  pike profile/manifest copies; strict motion coverage failed with
  `missing_reference_qa_gate:viewer_review`, and KG readiness classified
  `bodyweight_pike` as `not_ready`.

## 2026-06-09 Archetype Compiler Fail-Closed Default

- Tightened `scripts/motion_reference/compile_archetype_trace.py` so canonical
  archetype generation defaults to
  `dist/motion-reference/archetype_candidates/<exercise_id>/<exercise_id>.jsonl`
  instead of writing directly into
  `Sources/CamiFitApp/Resources/MotionDemos`.
- Added `--allow-app-resource-output` as an explicit opt-in for app MotionDemos
  writes, and still fail-closed for pending or rejected reference-capture
  profiles even when that flag is supplied.
- Generated manifests now declare
  `candidate_status=canonical_archetype_candidate` and state that the trace is
  candidate-only, not guide motion.
- Updated `scripts/motion_reference/README.md` so future agents compile
  archetype candidates into `dist/` and do not accidentally package generated
  motion for capture-required exercises.
- Verification passed:
  `python3 -m py_compile scripts/motion_reference/compile_archetype_trace.py`,
  default compile of `standing_miniband_hip_flexion` into
  `dist/motion-reference/archetype_candidates/...`, a negative app-output check
  proving pending `standing_miniband_hip_flexion` refuses MotionDemos output
  even with `--allow-app-resource-output`, a negative app-output check proving
  `bodyweight_plank` refuses MotionDemos output without the explicit flag,
  `python3 scripts/motion_reference/audit_motion_coverage.py --strict`,
  `python3 scripts/motion_reference/audit_kg_motion_readiness.py --summary-only`,
  and `git diff --check` for the touched files.

## 2026-06-09 Applications Relaunch / Installed Bundle Truth Surface

- Tightened `script/build_and_run.sh` so `run`, `--verify`, `--logs`, and
  `--telemetry` install the freshly built `dist/Momentum.app` into
  `/Applications/Momentum.app` before launching. This closes the stale-app gap
  where the Run button could launch a corrected dist bundle while the user saw
  an older app from Applications.
- Added `--install` as an explicit install-only script mode. The installer
  removes the previous `/Applications/Momentum.app`, copies the freshly signed
  bundle, then re-runs the packaged-resource verification against the installed
  copy.
- Verified `./script/build_and_run.sh --verify` builds, signs, installs, and
  launches `/Applications/Momentum.app/Contents/MacOS/CamiFitApp`.
- Verified installed bundle contents:
  14 app presets, 9 playable MotionDemos JSONL traces, 14 manifests, no
  `bodyweight_jumping_jack` preset/JSONL/manifest, and no playable JSONL for
  `standing_miniband_hip_flexion`, `resistance_band_reverse_curl`,
  `bench_lying_single_arm_dumbbell_tricep_extension`,
  `wide_grip_preacher_curl_with_ez_bar`, or
  `single_arm_chest_supported_incline_row`.
- Verified installed `bodyweight_lunge` JSONL and manifest SHA-256 hashes match
  the protected source resources exactly.
- Captured `/tmp/camifit_app_verify.png` after launching the Applications app.
  The visible Trackable presets section shows the cleaned nine guide-ready
  exercises and does not show Jumping Jack or the pending capture-required
  exercises as trackable presets. Pending items remain lower in the assessment
  catalog as recommendation/archetype entries.

## 2026-06-09 Pike Visual-Rig Quarantine

- Fixed-frame installed-app review of `bodyweight_pike` at the deepest pike
  frame (`CAMIFIT_GUIDE_FRAME_MS=2407`) confirmed the user-visible failure:
  the avatar head/neck detaches and the body reads as a broken rig despite the
  source trace passing loop and engine checks. Evidence screenshot:
  `/tmp/camifit_pike_apex_verify.png`.
- Quarantined Pike from Trackable presets by removing packaged
  `Sources/CamiFitApp/Resources/MotionDemos/bodyweight_pike.jsonl`, changing
  the profile to `viewer_status=pending_reference_capture`,
  `capture.status=pending_visual_rig_review`, and
  `normalizer.status=blocked_visual_rig_review_failed`.
- Preserved the Pexels source extraction as candidate-only repair evidence under
  `dist/motion-reference/bodyweight_pike/pexels_pike_31794279_800_3200/`.
  The packaged manifest now records
  `acceptance_status=blocked_visual_rig_review_failed`,
  `playable_trace_packaged=false`, the visual failure, and a repair plan.
- Updated app/KG gates so Pike maps to `Recommend only` with reasons
  `visual_rig_review_failed`, `avatar_head_neck_attachment_failed`, and
  `source_extraction_candidate_only`.
- Updated `script/build_and_run.sh` packaging verification so Pike must ship as
  preset + manifest only, with no playable JSONL, until the avatar rig passes
  visual review.
- Added `--require-trackable-reference-clips` to
  `scripts/motion_reference/audit_motion_coverage.py`; this is the current
  fail-closed product gate for trackable/playable guides while allowing
  metadata-only blocked presets to remain packaged.
- Verification passed:
  `python3 scripts/motion_reference/audit_motion_coverage.py --strict --require-trackable-reference-clips`,
  `python3 scripts/motion_reference/audit_kg_motion_readiness.py --summary-only`,
  focused Swift tests for app preset filtering, assignment catalog mapping,
  Pike no-JSONL packaging, and guide-ready replay, plus
  `./script/build_and_run.sh --verify`.
- Installed bundle proof after relaunch:
  `/Applications/Momentum.app` has 14 presets, 8 playable MotionDemos JSONL
  traces, and `bodyweight_pike` has preset + manifest but no playable JSONL.
  Screenshot `/tmp/camifit_after_pike_quarantine.png` shows Pike absent from
  Trackable presets and present only lower in the assessment catalog as
  `Recommend only`.

## 2026-06-09 Coach Allowlist / Planner Quarantine Regression

- Reviewed the read-only subagent runnable-surface audit. It found no current
  app-visible leak where reference-capture-required or rejected exercises become
  Trackable presets, runnable routine blocks, coach-startable exercises, or
  packaged playable MotionDemos.
- Added `AppExerciseTrackingGate.guideReadyPresetIDs` as the single app-side
  eight-preset guide-ready allowlist and routed `CodexAppServerClient` coach
  activation instructions through it. The stale six-item prompt copy no longer
  under-claims `machine_chest_supported_row` or
  `single_arm_cable_tricep_extension`.
- Added regression tests that the coach prompt contains every guide-ready ID
  and none of the reference-capture-required IDs; catalog coverage keeps all
  blocked exact mappings recommendation-only; exact guide-ready mappings match
  the app gate; and full-body planner projection never emits blocked preset IDs
  in routine blocks or preset mappings.
- Verification passed:
  `swift test --disable-sandbox --filter CodexAppServerClientTests --filter AssignmentExerciseCatalogTests --filter AssignmentWorkoutPlannerTests --filter AppExerciseSessionViewModelTests --filter CoachExerciseActionTests --filter AvatarHumanoidGLBAssetTests/testCaptureRequiredBundlesDoNotShipPlayableMotionDemos --filter AvatarHumanoidGLBAssetTests/testRejectedJumpingJackBundleDoesNotProduceGuideTimeline`
  with 52 tests, `python3 scripts/motion_reference/audit_motion_coverage.py
  --strict --require-trackable-reference-clips`,
  `python3 scripts/motion_reference/audit_kg_motion_readiness.py
  --summary-only`, and targeted `git diff --check`.
- Relaunch proof passed: `./script/build_and_run.sh --verify` installed and
  launched `/Applications/Momentum.app/Contents/MacOS/CamiFitApp`. The installed
  bundle has exactly eight playable MotionDemos JSONL traces matching
  `AppExerciseTrackingGate.guideReadyPresetIDs`; `bodyweight_jumping_jack` is
  absent, `bodyweight_pike` has manifest metadata only, and installed
  `bodyweight_lunge.jsonl` matches the protected source hash
  `04920c88fe91d6bd1c0c218bc8ae04477006bc97a6a1111e458d134f9f3a8a65`.

## 2026-06-09 Procedural Compiler Bypass Closure

- Closed the latent app-visible procedural fallback risk: `MotionDemoBundleStore`
  no longer falls back to `MotionDemoCompiler.compile(program:)` for guide
  playback. App guide rendering now requires the preset ID to be in
  `AppExerciseTrackingGate.guideReadyPresetIDs` and to have an eligible packaged
  MotionDemos JSONL trace.
- Added regression coverage proving an unlisted synthetic program can still be
  compiled by the engine test helper but cannot become a guide timeline through
  `MotionDemoBundleStore`. Added a source-level guard that fails if
  `Sources/CamiFitApp` directly calls `MotionDemoCompiler.compile`, keeping
  app-visible guide playback on the packaged-trace path.
- Verification passed:
  `swift test --disable-sandbox --filter AppExerciseSessionViewModelTests --filter AssignmentExerciseCatalogTests --filter AssignmentWorkoutPlannerTests --filter CoachExerciseActionTests --filter CodexAppServerClientTests --filter AvatarHumanoidGLBAssetTests --filter MediaPipePoseProviderTests/testGuideReadyMotionDemoTracesDecodeAndReplayThroughEngine`
  with 61 tests, `python3 scripts/motion_reference/audit_motion_coverage.py
  --strict --require-trackable-reference-clips`,
  `python3 scripts/motion_reference/audit_kg_motion_readiness.py
  --summary-only`, and targeted `git diff --check`.

## 2026-06-09 Source-Provenance / Machine Row License Demotion

- Strengthened the source-preserving motion audit so every accepted playable
  reference must explicitly carry `acceptance_status`,
  `playable_trace_packaged=true`, source/license/attribution metadata,
  `source_video`, `raw_trace`, `normalizer`, and `output_trace`. The protected
  lunge path also requires `golden_trace` and `candidate_trace`, preserving the
  original lunge guide as the comparator rather than allowing the extractor to
  overwrite it.
- Updated accepted first-party/protected manifests for lunge, push-up, squat,
  plank, cable tricep extension, preacher curl, and suspension tricep press.
  Lunge remains protected by hash
  `04920c88fe91d6bd1c0c218bc8ae04477006bc97a6a1111e458d134f9f3a8a65`.
- Demoted `machine_chest_supported_row` from guide-ready to
  reference-capture-required because the retained Commons source page for
  `File:How_to_properly_do_Machine_T-Bar_Rows.webm` still marks the imported
  file as `License review needed`. Its candidate trace remains under
  `dist/motion-reference/` for analysis, but the app ships no playable
  `Sources/CamiFitApp/Resources/MotionDemos/machine_chest_supported_row.jsonl`.
- Updated app gates, assignment catalog coverage, coach/action tests, packaging
  verification, KG readiness reason codes, and the motion-reference README so
  Machine Row reports `pending_source_license_review` and
  `external_commons_license_review_needed` instead of silently looking
  guide-ready.
- Verification passed:
  `python3 scripts/motion_reference/test_audit_motion_coverage.py`,
  `python3 scripts/motion_reference/audit_motion_coverage.py --strict --require-trackable-reference-clips`,
  `python3 scripts/motion_reference/audit_kg_motion_readiness.py --summary-only --write-report scripts/motion_reference/kg_motion_readiness.assessment.v0.json`,
  `python3 -m py_compile scripts/motion_reference/audit_motion_coverage.py scripts/motion_reference/test_audit_motion_coverage.py scripts/motion_reference/audit_kg_motion_readiness.py`,
  and
  `swift test --disable-sandbox --filter AppExerciseSessionViewModelTests --filter AssignmentExerciseCatalogTests --filter AssignmentWorkoutPlannerTests --filter CoachExerciseActionTests --filter CodexAppServerClientTests --filter AvatarHumanoidGLBAssetTests --filter MediaPipePoseProviderTests/testGuideReadyMotionDemoTracesDecodeAndReplayThroughEngine --filter MachineChestSupportedRowAcceptanceTests`
  with 63 Swift tests passing.
- Relaunch proof passed: `./script/build_and_run.sh --verify` installed and
  launched `/Applications/Momentum.app/Contents/MacOS/CamiFitApp`. The
  installed bundle has exactly 7 playable MotionDemos JSONL traces:
  `bodyweight_lunge`, `bodyweight_plank`, `bodyweight_pushup`,
  `bodyweight_squat`, `single_arm_cable_tricep_extension`,
  `single_arm_dumbbell_preacher_curl`, and `suspension_tricep_press`.
  Machine Row has preset + manifest metadata only, with
  `acceptance_status=pending_source_license_review` and
  `playable_trace_packaged=false`; installed
  `bodyweight_lunge.jsonl` still hashes to the protected golden value above.

## 2026-06-09 Mutable Preset Allowlist Closure

- Closed a remaining fail-open app path where an unknown or user-generated
  preset from Application Support could become Trackable merely because it was
  not listed as reference-capture-required. `AppExerciseSessionViewModel`
  now surfaces only preset IDs in `AppExerciseTrackingGate.guideReadyPresetIDs`,
  the candidate preset JSON must match the bundled canonical preset JSON, and
  the first candidate directory wins on ID collisions so mutable user presets
  cannot shadow bundled guide-ready definitions.
- Closed inline routine execution as a guide bypass. Inline
  `ExerciseProgram` blocks are now unguided by `WorkoutRoutine`, rejected by
  the legacy view-model routine starter, and rejected by `RoutineRunner` before
  `RoutineCompiler` can compile or activate them. Generated exercises may be
  stored as drafts, but they cannot become Trackable/runnable guidance without
  accepted motion-reference promotion.
- Closed guide manifest fallback. `MotionDemoBundleStore` now fails closed if
  the adjacent manifest is missing or undecodable, and guide eligibility
  requires an `acceptance_status` beginning with `accepted` or
  `protected_golden` plus a trainer/external reference source kind. It also
  requires `playable_trace_packaged=true`, source video, raw trace, normalizer,
  output trace, license/attribution, a recorded `golden_comparison` decision,
  and structured `visual_review` + `engine_replay` pass evidence. A packaged
  JSONL alone is no longer sufficient to create a guide timeline.
- Added regression coverage that a saved generated exercise with no accepted
  reference trace remains absent from Trackable and cannot be selected; a
  generated draft with a guide-ready ID cannot shadow the bundled canonical
  preset; inline routine blocks cannot start via either routine path; missing
  or unaccepted manifests are not guide-eligible; every packaged playable JSONL
  and every guide-eligible manifest must match
  `AppExerciseTrackingGate.guideReadyPresetIDs`; and `PresetMergeTests` proves
  the bundled candidate wins over a later mutable duplicate.
- Tightened the motion-reference audit so accepted guide traces require an
  explicit golden-comparison decision. Non-comparable movements must say why no
  protected comparator applies yet; the protected lunge manifest records the
  real `golden_comparison.json` report and keeps the shipped lunge trace as the
  protected app golden.
- Added `artifact_integrity` byte counts and SHA-256 hashes for every accepted
  source-preserving artifact: source video, raw trace, normalizer, output trace,
  and lunge candidate/golden comparison artifacts. The strict audit now
  recomputes those values and also rejects promoted manifests with declared
  artifacts but no integrity block, even before profile acceptance is consulted.
- Tightened the normal closeout gate: `scripts/run_monorepo_gates.sh` now runs
  `audit_motion_coverage.py --strict --require-trackable-reference-clips`, and
  strict mode rejects orphan playable JSONLs or promoted manifests that are not
  tied to both a packaged preset and a motion profile.
- Verification passed:
  `swift test --disable-sandbox --filter AppExerciseSessionViewModelTests --filter AssignmentExerciseCatalogTests --filter AssignmentWorkoutPlannerTests --filter CoachExerciseActionTests --filter CodexAppServerClientTests --filter AvatarHumanoidGLBAssetTests --filter MediaPipePoseProviderTests/testGuideReadyMotionDemoTracesDecodeAndReplayThroughEngine --filter MachineChestSupportedRowAcceptanceTests --filter PresetMergeTests --filter SaveGeneratedExerciseTests --filter RoutineInlineExerciseTests`
  `--filter RoutineRunnerTests --filter RoutinePresentationTests`
  with 79 Swift tests, plus
  `python3 scripts/motion_reference/audit_motion_coverage.py --strict --require-trackable-reference-clips`,
  `python3 scripts/motion_reference/audit_kg_motion_readiness.py --summary-only`,
  `python3 scripts/motion_reference/test_audit_motion_coverage.py` (6 tests),
  `bash -n scripts/run_monorepo_gates.sh`, and Python
  bytecode compilation for the motion audit scripts.
- Relaunch proof passed after this hardening:
  `./script/build_and_run.sh --verify` installed and launched
  `/Applications/Momentum.app/Contents/MacOS/CamiFitApp`. The installed app
  resource bundle still has exactly 7 playable MotionDemo JSONLs, Machine Row
  still has no JSONL and remains `pending_source_license_review`, and installed
  lunge still hashes to
  `04920c88fe91d6bd1c0c218bc8ae04477006bc97a6a1111e458d134f9f3a8a65`.
  Fresh screenshot `/tmp/camifit_after_manifest_evidence_relaunch.png` shows
  the visible Trackable list limited to the seven trusted exercises while
  guide-less exercises such as Bodyweight Pike and Bench-Lying Single-Arm
  remain lower in the assessment catalog as recommendation-only or archetype
  entries.

## 2026-06-09 Pending Source-Search Gate Closure

- Closed the next fail-open documentation gap: pending/reference-capture
  exercises now need source-search/rejection records while they are still
  quarantined, not only after promotion. `audit_motion_coverage.py --strict`
  checks packaged pending presets and profile-only extras such as
  `bodyweight_jumping_jack`; missing or malformed `rejected_candidates` now
  fails the gate.
- Added focused audit coverage for the pending-source-search rule:
  one test proves a `viewer_status=pending_reference_capture` profile with no
  search/rejection record fails, and one proves an explicit rejected candidate
  record passes without making the exercise guide-ready. Added direct strict
  inventory tests proving profile-only pending extras still get checked and a
  pending playable JSONL still fails.
- Filled the uncovered ledgers exposed by the new gate:
  `bodyweight_pike` now records the Pexels yoga-flow candidate as
  `rejected - visual rig review failed`; `machine_chest_supported_row`,
  `single_arm_chest_supported_incline_row`, and the profile-only
  `bodyweight_jumping_jack` records now carry complete conservative
  source/license/attribution/decision/reason fields for retained rejected
  candidates.
- Fixed the stale engine test that still expected the protected lunge trace to
  have 89 frames. After subagent review flagged the first fix as too weak, the
  test now also checks the protected lunge's smoothed descent/ascent phase shape
  so mid-rep wobble or extra partial motion cannot pass on count alone. The
  current protected app golden remains 108 frames and still hashes to
  `04920c88fe91d6bd1c0c218bc8ae04477006bc97a6a1111e458d134f9f3a8a65`.
- Verification passed:
  `python3 -m py_compile scripts/motion_reference/audit_motion_coverage.py scripts/motion_reference/test_audit_motion_coverage.py`,
  `python3 scripts/motion_reference/test_audit_motion_coverage.py` (12 tests),
  `scripts/motion_reference/audit_motion_coverage.py --strict --require-trackable-reference-clips`,
  `scripts/motion_reference/audit_kg_motion_readiness.py --summary-only`,
  `swift test --disable-sandbox --filter MediaPipePoseProviderTests/testBundledBodyweightLungeMotionDemoTraceDecodesAndCountsOneRep`,
  and the reusable `scripts/run_monorepo_gates.sh`.
- Relaunch/install proof passed after the packaged Pike manifest update:
  `./script/build_and_run.sh --verify` installed
  `/Applications/Momentum.app` and process
  `/Applications/Momentum.app/Contents/MacOS/CamiFitApp` is running. The
  installed MotionDemos bundle contains exactly seven playable JSONLs:
  `bodyweight_lunge`, `bodyweight_plank`, `bodyweight_pushup`,
  `bodyweight_squat`, `single_arm_cable_tricep_extension`,
  `single_arm_dumbbell_preacher_curl`, and `suspension_tricep_press`. Installed
  `bodyweight_pike.manifest.json` remains
  `acceptance_status=blocked_visual_rig_review_failed`,
  `playable_trace_packaged=false`, and includes the rejected visual-rig source
  record; installed lunge is still 108 frames with the protected hash above.

## 2026-06-09 Live-App Review Gate Closure

- Added a structured `live_app_review` promotion requirement for accepted guide
  manifests. The strict motion audit now requires `status=passed`, evidence,
  installed `app_bundle`, `installed_playable_jsonls`, and exact
  `installed_playable_trace_ids` membership for the manifest's own
  `exercise_id`; `MotionDemoManifest` also refuses guide eligibility when this
  runtime field is absent or the current exercise is missing from the installed
  trusted-guide list.
- Populated the seven trusted guide manifests with current installed-app proof:
  `./script/build_and_run.sh --verify` installed/launched
  `/Applications/Momentum.app`, and the installed MotionDemos bundle contained
  exactly seven playable JSONL traces. Each `live_app_review` now records the
  seven installed guide IDs explicitly. Per-exercise avatar/rig quality remains
  recorded separately under each manifest's `visual_review`.
- Added regression coverage so an otherwise source-reviewed licensed external
  manifest still fails app guide eligibility without `live_app_review`.
- Validation evidence:
  `jq empty Sources/CamiFitApp/Resources/MotionDemos/*.manifest.json scripts/motion_reference/exercise_motion_profiles.json`,
  `python3 -m py_compile scripts/motion_reference/audit_motion_coverage.py scripts/motion_reference/test_audit_motion_coverage.py`,
  `python3 scripts/motion_reference/test_audit_motion_coverage.py` (12 tests),
  `scripts/motion_reference/audit_motion_coverage.py --strict --require-trackable-reference-clips`,
  `scripts/motion_reference/audit_kg_motion_readiness.py --summary-only`, and
  `swift test --disable-sandbox --filter AvatarHumanoidGLBAssetTests/testMotionDemoManifestFailsClosedWhenMissingOrUnaccepted --filter AvatarHumanoidGLBAssetTests/testGuideReadyGateMatchesPlayableBundleAndAcceptedManifests`.

## 2026-06-09 Runtime Manifest-ID Binding Closure

- Closed the remaining runtime fail-open path found during subagent review:
  `MotionDemoBundleStore.timeline(for:)` now requires
  `manifest.isGuideEligible(for: program.id)`, binding the adjacent manifest's
  `exercise_id` to the requested preset/JSONL ID before a guide timeline can
  load. An otherwise accepted copied manifest now fails if its ID does not match
  the trace being requested.
- Updated the guide-ready bundle parity test to use the same ID-bound manifest
  predicate and added regression assertions proving an accepted manifest passes
  for `test` but fails for `copied_manifest_wrong_trace` and blank IDs.
- Subagent follow-up review reported no findings after the runtime binding fix.
- Verification passed:
  `swift test --disable-sandbox --filter AvatarHumanoidGLBAssetTests/testMotionDemoManifestFailsClosedWhenMissingOrUnaccepted --filter AvatarHumanoidGLBAssetTests/testGuideReadyGateMatchesPlayableBundleAndAcceptedManifests`,
  `python3 scripts/motion_reference/test_audit_motion_coverage.py`,
  `scripts/motion_reference/audit_motion_coverage.py --strict --require-trackable-reference-clips`,
  and `scripts/run_monorepo_gates.sh`.
- Fresh relaunch/install proof passed after the runtime binding fix:
  `./script/build_and_run.sh --verify` installed
  `/Applications/Momentum.app` and process
  `/Applications/Momentum.app/Contents/MacOS/CamiFitApp` is running. The
  installed MotionDemos bundle contains exactly seven playable JSONLs:
  `bodyweight_lunge`, `bodyweight_plank`, `bodyweight_pushup`,
  `bodyweight_squat`, `single_arm_cable_tricep_extension`,
  `single_arm_dumbbell_preacher_curl`, and `suspension_tricep_press`. There is
  no installed `bodyweight_jumping_jack` JSONL/manifest, no installed
  `bodyweight_pike.jsonl`, and installed `bodyweight_lunge.jsonl` has 108 lines
  with SHA-256
  `04920c88fe91d6bd1c0c218bc8ae04477006bc97a6a1111e458d134f9f3a8a65`.

## 2026-06-09 Trackable And Runnable Surface Audit

- Re-audited app surfaces that could expose guide-less exercises as Trackable or
  runnable. The app preset loader only emits `AppExerciseTrackingGate`
  `guideReadyPresetIDs`, requires the packaged preset bytes to match the
  approved bundle resource, and rejects reference-capture IDs through
  `selectPreset`, `programForPreset`, and routine start gates.
- A read-only subagent audit found no confirmed path where
  `referenceCaptureRequiredPresetIDs` become selectable Trackable presets or
  start/compile as runnable routine blocks. The remaining residual surface was
  stale/hand-authored `future-routine` JSON that names a blocked exercise such
  as `bodyweight_pike` directly as a preset; the app already displays/handles
  that as unavailable rather than runnable.
- Hardened tests around that boundary:
  `AppExerciseSessionViewModelTests` now asserts the visible preset set equals
  `guideReadyPresetIDs`; `RoutineCompilerTests` proves a mixed routine cannot
  compile until using its guided-only subset; `RoutinePresentationTests` proves
  a stale Pike preset routine presents as unavailable through the app-gated
  compiler; and `RoutineRunnerTests` proves that stale Pike preset routine is
  rejected before runner start without changing selected state.
- Focused verification passed:
  `swift test --disable-sandbox --filter AppExerciseSessionViewModelTests/testDefaultViewModelDiscoversPackagedPresetResources --filter AppExerciseSessionViewModelTests/testLoadsBundledPresetListAndSelectsGuideReadyPresetsOnly --filter RoutineCompilerTests/testCompilerRejectsMixedRoutineUntilGuidedSubsetIsUsed --filter RoutineCompilerTests/testCompilerRejectsCatalogOnlyRoutineBlock --filter RoutinePresentationTests/testSummaryTreatsReferenceCapturePresetRoutineAsUnavailable --filter RoutineRunnerTests/testReferenceCapturePresetRoutineIsRejectedBeforeRunnerStart`.
- Full verification also passed with `scripts/run_monorepo_gates.sh`, including
  strict motion coverage (`pending_reference_captures=7 failures=0`) and KG
  motion readiness (`app_guide_ready=7`).

## 2026-06-09 Guide-Ready Inventory Gate Closure

- Added `--require-guide-ready-inventory` to the strict motion coverage audit
  and wired it into `scripts/run_monorepo_gates.sh`. The gate now parses
  `AppExerciseTrackingGate.swift` directly and requires the packaged playable
  JSONL inventory to exactly equal `guideReadyPresetIDs`, with no overlap with
  `referenceCaptureRequiredPresetIDs`.
- The inventory gate also checks each guide-ready exercise has a packaged
  preset, motion profile, accepted capture status, manifest, packaged playable
  trace flag, matching manifest `exercise_id`, and `live_app_review`
  installed-app IDs/counts that match the current packaged playable inventory.
  This turns the "seven trusted guides only" state into an automated fail-closed
  invariant instead of a manual bundle inspection.
- A read-only subagent audit recommended this extra standalone inventory gate
  because the exact playable bundle count was previously distributed across
  Swift tests, manifest metadata, and Python audits. I reviewed that finding and
  implemented the shared Python verifier rather than relying on one app-side
  parity test.
- Focused verification passed:
  `python3 -m py_compile scripts/motion_reference/audit_motion_coverage.py scripts/motion_reference/test_audit_motion_coverage.py`,
  `python3 scripts/motion_reference/test_audit_motion_coverage.py` (15 tests),
  and `scripts/motion_reference/audit_motion_coverage.py --strict --require-trackable-reference-clips --require-guide-ready-inventory`
  (`guide_ready=7 reference_capture_required=8 playable_jsonls=7 failures=0`).
- Full verification passed with `scripts/run_monorepo_gates.sh`, including the
  stricter motion-reference coverage gate above and KG motion readiness still at
  `app_guide_ready=7`.

## 2026-06-09 Legacy Routine Recommendation Closure

- Ran a second read-only subagent audit across planner, routine, runner, coach
  action, and chat-regimen paths. It found no app-runnable pending exercise
  path: Trackable presets, `programForPreset`, `RoutineRunner`, and coach action
  dispatch all recheck `AppExerciseTrackingGate` before execution.
- Closed the residual non-execution leak the audit did find: legacy
  `future-routine` / `camifit-routine` JSON can no longer display or save a
  freehand routine when it references a blocked/non-guide-ready preset such as
  `bodyweight_pike`, a catalog-only exercise, or an inline draft. The parser now
  returns an invalid routine card and names the non-guide-ready refs.
- Tightened guided-subset handling so stale blocked preset blocks are filtered
  by the same app-gated compiler predicate used for execution. A mixed routine
  can still start the safe guide-ready blocks, but blocked presets do not count
  as guided just because they are syntactically `.preset(...)`.
- Hardened the legacy `AppExerciseSessionViewModel.startRoutine` path so it
  validates the target block before mutating `activeRoutine`,
  `activeRoutineBlockIndex`, phase, or selected exercise state. This keeps the
  older API fail-closed even though the current UI routes routine execution
  through `RoutineRunner`.
- Focused verification passed:
  `swift test --disable-sandbox --filter ChatRegimenParseTests --filter AppExerciseSessionViewModelTests/testStartRoutineRejectsReferenceCapturePresetWithoutMutatingRoutineState --filter AssignmentWorkoutPlannerTests/testReferenceCaptureRequiredPikePromptStaysCatalogRecommendationOnly --filter RoutinePresentationTests/testSummarySkipsStaleReferenceCapturePresetWhenGuideReadySubsetCanRun --filter RoutinePresentationTests/testSummaryTreatsReferenceCapturePresetRoutineAsUnavailable`
  and the broader related suite
  `swift test --disable-sandbox --filter AssignmentWorkoutPlannerTests --filter RoutinePresentationTests --filter RoutineCompilerTests --filter RoutineRunnerTests`.
- Full verification passed again with `scripts/run_monorepo_gates.sh`, including
  strict motion coverage with `guide_ready=7`, `reference_capture_required=8`,
  `playable_jsonls=7`, `failures=0`, and KG motion readiness with
  `app_guide_ready=7`.

## 2026-06-09 Tracking Gate Drift Closure

- Tightened `--require-guide-ready-inventory` again so the Python motion audit
  now treats `scripts/motion_reference/exercise_motion_profiles.json` and
  `AppExerciseTrackingGate.referenceCaptureRequiredPresetIDs` as a locked pair.
  Every pending motion profile, including profile-only quarantine entries such
  as `bodyweight_jumping_jack`, must be listed in the Swift
  reference-capture-required set; stale Swift IDs without pending profiles now
  fail the gate.
- This closes a maintenance gap where Swift tests checked the relationship, but
  the reusable motion-reference audit only used the reference-capture set to
  block playable JSONLs and guide-ready overlap. Future promotion/demotion now
  has to update the motion profile and app tracking gate together before the
  monorepo gate passes.
- Focused verification passed:
  `python3 -m py_compile scripts/motion_reference/audit_motion_coverage.py scripts/motion_reference/test_audit_motion_coverage.py`,
  `python3 scripts/motion_reference/test_audit_motion_coverage.py` (16 tests),
  and `scripts/motion_reference/audit_motion_coverage.py --strict --require-trackable-reference-clips --require-guide-ready-inventory`
  (`guide_ready=7 reference_capture_required=8 playable_jsonls=7 failures=0`).
- Full verification passed with `scripts/run_monorepo_gates.sh`, including the
  16-test motion-reference suite and strict guide-ready inventory line
  `guide_ready=7 reference_capture_required=8 playable_jsonls=7`.
- Relaunch/install proof passed with
  `CAMIFIT_GUIDE_EXERCISE=bodyweight_lunge ./script/build_and_run.sh --verify`.
  `/Applications/Momentum.app` is running as `CamiFitApp`; the installed
  `CamiFit_CamiFitApp.bundle/MotionDemos` directory contains exactly seven
  playable JSONLs:
  `bodyweight_lunge`, `bodyweight_plank`, `bodyweight_pushup`,
  `bodyweight_squat`, `single_arm_cable_tricep_extension`,
  `single_arm_dumbbell_preacher_curl`, and `suspension_tricep_press`. There is
  no installed `bodyweight_jumping_jack*` resource and no installed
  `bodyweight_pike.jsonl`. The installed `bodyweight_lunge.jsonl` has 108 lines
  and SHA-256
  `04920c88fe91d6bd1c0c218bc8ae04477006bc97a6a1111e458d134f9f3a8a65`.

## 2026-06-09 Runtime API Boundary Closure

- Closed a lower-level routine-start gap: `AppExerciseSessionViewModel.startRoutine`
  now validates every routine block before mutating active routine state, not
  only the requested starting block. A mixed hand-built routine with
  `bodyweight_squat` first and stale `bodyweight_pike` later now fails before it
  can become active.
- Closed direct activation bypasses: public
  `AppExerciseSessionViewModel.activateProgram(_:)` and
  `applyExerciseFrameResult(_:program:)` now require the supplied
  `ExerciseProgram` to exactly match the approved bundled guide-ready preset.
  Generated/shadow programs with the same ID, or unknown programs with valid
  syntax, can no longer become selected or receive frame results by bypassing
  preset selection.
- Closed inline-routine presentation drift: `RoutineCompiler` now rejects inline
  routine programs by default until they go through accepted motion-reference
  promotion. Saved/imported inline routines therefore present as unavailable
  instead of appearing runnable just because their JSON dry-runs.
- Focused verification passed:
  `swift test --disable-sandbox --filter SaveGeneratedExerciseTests --filter RoutineCompilerTests/testCompilerRejectsInlineRoutineBlockUntilMotionReferencePromotion --filter RoutinePresentationTests/testSummaryTreatsInlineRoutineAsUnavailableUntilMotionReferencePromotion --filter AppExerciseSessionViewModelTests/testStartRoutineRejectsLaterReferenceCapturePresetWithoutMutatingRoutineState`.
- Broader app guard verification passed:
  `swift test --disable-sandbox --filter AppExerciseSessionViewModelTests --filter RoutineCompilerTests --filter RoutinePresentationTests --filter RoutineRunnerTests --filter SaveGeneratedExerciseTests --filter RoutineInlineExerciseTests --filter CoachExerciseActionTests --filter ChatRegimenParseTests --filter AssignmentWorkoutPlannerTests --filter AssignmentExerciseCatalogTests`
  (75 tests).
- Full verification passed again with `scripts/run_monorepo_gates.sh`; strict
  motion coverage still reports
  `guide_ready=7 reference_capture_required=8 playable_jsonls=7 failures=0`.
- Relaunch/install proof passed again with
  `CAMIFIT_GUIDE_EXERCISE=bodyweight_lunge ./script/build_and_run.sh --verify`.
  `/Applications/Momentum.app` is running as `CamiFitApp`, the installed
  MotionDemos JSONL set is still exactly the seven trusted guide-ready traces,
  no installed `bodyweight_jumping_jack*` resource or `bodyweight_pike.jsonl`
  exists, and installed `bodyweight_lunge.jsonl` still has 108 lines with SHA-256
  `04920c88fe91d6bd1c0c218bc8ae04477006bc97a6a1111e458d134f9f3a8a65`.

## 2026-06-09 Guided Subset / Live App Closure

- Tightened the mixed-routine copy so any routine that can only run its
  guide-ready subset presents as `Guided subset`, not a generic runnable
  routine. This keeps stale or hand-authored routines with pending references
  honest while still allowing the safe guided blocks to start.
- Focused presentation verification passed:
  `swift test --disable-sandbox --filter RoutinePresentationTests` (7 tests).
- Broader fail-closed guard verification passed:
  `swift test --disable-sandbox --filter 'AppExerciseSessionViewModelTests|RoutineCompilerTests|RoutinePresentationTests|RoutineRunnerTests|SaveGeneratedExerciseTests|RoutineInlineExerciseTests|CoachExerciseActionTests|ChatRegimenParseTests|AssignmentWorkoutPlannerTests|AssignmentExerciseCatalogTests'`
  (75 tests).
- Full verification passed again with `scripts/run_monorepo_gates.sh`, including
  Python KG tests (`156 passed`), Swift tests, the 16-test motion-reference
  suite, strict motion coverage
  `guide_ready=7 reference_capture_required=8 playable_jsonls=7 failures=0`,
  and KG motion readiness `app_guide_ready=7`.
- Relaunch/install proof passed with
  `CAMIFIT_GUIDE_EXERCISE=bodyweight_lunge ./script/build_and_run.sh --verify`;
  the build codesigned, installed `/Applications/Momentum.app`, and launched
  `/Applications/Momentum.app/Contents/MacOS/CamiFitApp`.
- Direct installed-resource inspection confirms the app bundle has exactly the
  seven playable MotionDemos JSONLs:
  `bodyweight_lunge`, `bodyweight_plank`, `bodyweight_pushup`,
  `bodyweight_squat`, `single_arm_cable_tricep_extension`,
  `single_arm_dumbbell_preacher_curl`, and `suspension_tricep_press`. There is
  no installed `bodyweight_jumping_jack*` resource and no installed
  `bodyweight_pike.jsonl`. Installed `bodyweight_lunge.jsonl` still has 108
  lines and SHA-256
  `04920c88fe91d6bd1c0c218bc8ae04477006bc97a6a1111e458d134f9f3a8a65`.
- Fresh live-app screenshot:
  `/tmp/camifit_fail_closed_live_20260609_1042.png`. The visible Exercises tab
  shows only the seven trusted Trackable presets; pending/new exercises,
  including Bench-Lying Single-Arm Dumbbell Tricep Extension and Bodyweight
  Pike, remain in the Assessment catalog as non-trackable recommendation rows.

## 2026-06-09 Visual Regression Demotion Closure

- User screenshots showed that the earlier seven-guide inventory was too
  permissive. The fixed-frame installed-app review matched bad avatar renders
  for `single_arm_dumbbell_preacher_curl`,
  `suspension_tricep_press`, and `bodyweight_plank`.
- A read-only subagent audit identified the same likely screenshot matches and
  recommended demoting rather than polishing around bad source/rig data. I
  reviewed the deterministic app captures and applied the stricter fail-closed
  policy.
- `AppExerciseTrackingGate.guideReadyPresetIDs` is now exactly four IDs:
  `bodyweight_lunge`, `bodyweight_pushup`, `bodyweight_squat`, and
  `single_arm_cable_tricep_extension`.
- `AppExerciseTrackingGate.referenceCaptureRequiredPresetIDs` now includes
  `bodyweight_plank`, `single_arm_dumbbell_preacher_curl`, and
  `suspension_tricep_press`; their playable MotionDemo JSONLs were removed from
  the app bundle. Their manifests and motion profiles remain as
  `blocked_visual_rig_review_failed` / `pending_visual_rig_review` metadata.
- The default future routine no longer uses `bodyweight_plank`; it uses the
  protected lunge guide instead. Planner, catalog, runner, and app-session tests
  now assert these demoted exercises remain recommendation-only or fail closed
  before state mutation.
- Focused verification passed:
  `swift test --disable-sandbox --filter 'AppExerciseSessionViewModelTests|RoutineRunnerTests|RoutinePresentationTests|AssignmentExerciseCatalogTests|AssignmentWorkoutPlannerTests|ChatRegimenParseTests|AvatarHumanoidGLBAssetTests|MediaPipePoseProviderTests|SingleArmDumbbellPreacherCurlAcceptanceTests'`
  (79 tests).
- Strict motion coverage passed:
  `scripts/motion_reference/audit_motion_coverage.py --strict --require-trackable-reference-clips --require-guide-ready-inventory`
  with `guide_ready=4 reference_capture_required=11 playable_jsonls=4
  failures=0`.
- KG readiness was regenerated with
  `scripts/motion_reference/audit_kg_motion_readiness.py --summary-only
  --write-report scripts/motion_reference/kg_motion_readiness.assessment.v0.json`.
  It reports `app_guide_ready=4`; generated KG catalog counts are
  `guide_ready=1`, `archetype_demo_only=14`, `recommend_only=35`, and
  `mapped_incomplete=18`.
- Full verification passed with `scripts/run_monorepo_gates.sh`, including
  Python KG tests (`156 passed`), full Swift tests (`374 tests`), the 16-test
  motion-reference suite, strict motion coverage
  `guide_ready=4 reference_capture_required=11 playable_jsonls=4 failures=0`,
  and KG motion readiness `app_guide_ready=4`.
- Relaunch/install proof passed with
  `CAMIFIT_GUIDE_EXERCISE=bodyweight_lunge ./script/build_and_run.sh --verify`.
  `/Applications/Momentum.app` is running as `CamiFitApp`, and direct installed
  resource inspection shows exactly four playable MotionDemos JSONLs:
  `bodyweight_lunge`, `bodyweight_pushup`, `bodyweight_squat`, and
  `single_arm_cable_tricep_extension`.
- Direct installed-resource inspection found no installed playable JSONL for
  `bodyweight_plank`, `single_arm_dumbbell_preacher_curl`, or
  `suspension_tricep_press`.
- Fresh live-app screenshot:
  `/tmp/camifit_demoted_visual_regression_live_20260609.png`. The visible
  Exercises tab shows the four Trackable presets above; Pike,
  Bench-Lying Single-Arm Dumbbell Tricep Extension, and other not-ready rows are
  in the Assessment catalog as recommendation-only.

## Definition Of Done

The assignment closeout is done when the visible app or submitted dashboard can
demonstrate:

- Prompt + time input.
- Graph-driven workout generation.
- Injury-aware filtering through anatomy traversal.
- Equipment-aware filtering and safe alternatives.
- Provenance traces with graph paths and reason codes.
- KG-backed member copilot with quick prompts and charts.
- Resolver and safety tests.
- Comprehensive README with architecture, run instructions, tradeoffs, AI usage,
  production evaluation, and examples.
