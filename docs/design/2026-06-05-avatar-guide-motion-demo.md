# Avatar Guide Motion Demo

**Date:** 2026-06-05  
**Status:** Frozen motion-source path plus neutral riggable avatar slice  
**Scope:** the center hero feed toggle that replaces camera input with a gradient + avatar reenactment of the active exercise.

## Decision

The avatar guide must be driven by the same landmark contract as tracking:

```
ExerciseProgram / motion archetype
  -> generated PoseFrame timeline
  -> avatar renderer

Camera frame
  -> MediaPipe Pose Landmarker
  -> PoseFrame
  -> exercise engine
```

The motion spec does **not** go into MediaPipe. MediaPipe receives images and emits body landmarks. Official MediaPipe Pose Landmarker docs describe outputs as normalized image landmarks plus 3D world landmarks, and the running modes as `IMAGE`, `VIDEO`, and `LIVE_STREAM`. CamiFit's worker/runtime boundary already matches this: MediaPipe output is decoded into `PoseFrame` with `left.*`, `right.*`, and locked `primary.*` landmarks.

So the transform we need is not "motion spec -> MediaPipe"; it is:

1. `CatalogExercise` / FitGraph selection produces or references a trackable movement archetype.
2. The archetype compiles to an `ExerciseProgram` for tracking.
3. The same archetype compiles to a `MotionDemoTimeline` of `PoseFrame` keyframes for instruction.
4. Tests run the generated timeline through the real engine where possible, making the guide auditable instead of decorative.

## Current slice

Implemented now:

- `MotionDemoCompiler` in `CamiFitEngine` turns the selected `ExerciseProgram` into a looping `MotionDemoTimeline`.
- `MotionDemoTimeline.source` explicitly records the current source as
  `procedural_fallback` and the frozen canonical source as
  `trainer_reference_trace`. This keeps the temporary path honest in code.
- `AvatarDemoStage` renders the active program's timeline through a SceneKit
  neutral mannequin rig over a gradient stage.
- The hero card gets a top `Guide` / `Camera` toggle. Starting live camera or bundled demo returns the feed to tracking mode.
- Tests load the four bundled presets and assert each compiles into valid `PoseFrame`s. The squat guide timeline is also run through `EngineTraceRecorder` and must count one rep.

This is intentionally a v1 archetype compiler and riggable mannequin renderer, not
a full inverse-kinematics system or a captured trainer clip.

## Frozen source path

The production path for instructional motion is now frozen:

```
trainer reference video
  -> MediaPipe Pose Landmarker in deterministic VIDEO mode
  -> normalized/smoothed PoseFrame + world-landmark trace
  -> contact/phase annotations
  -> MotionDemoTimeline
  -> rig retargeting / mannequin or avatar playback
```

The current procedural compiler remains only as a fallback until those reference
clips exist. It should not be expanded into a second competing source of truth.
When a real clip is available, the loader should prefer the bundled reference
trace and use the procedural archetype only if no trace exists.

## Riggable mannequin contract

The guide renderer now uses a named SceneKit mannequin rig instead of rebuilding a
visible stick skeleton every frame. The rig owns stable nodes such as:

- `rig.head`
- `rig.spine`
- `rig.pelvis`
- `rig.near.upperArm`
- `rig.near.forearm`
- `rig.near.upperLeg`
- `rig.near.lowerLeg`
- `rig.near.foot`
- matching `rig.far.*` support-side nodes

Those nodes are driven from the same `PoseFrame` joint anchors. That gives us a
local neutral/mannequin avatar now while keeping a clean replacement point for a
future rigged mesh. A future mesh import should retarget to this node map rather
than changing the exercise engine contract.

## Grounding correction

A visual review of the lunge guide exposed a real data bug: the first pass bent the
front knee by moving `primary.ankle` upward from `y=0.84` to `y=0.70`. In image
landmark coordinates that means the foot lifts toward the top of the frame, so the
avatar looked as if the front foot came off the floor near the end of the rep.

The corrected lunge timeline treats both feet as planted contact constraints:

- `primary.heel` and `primary.foot.index` keep stable `x`/`y` anchors.
- `secondary.heel` and `secondary.foot.index` keep stable `x`/`y` anchors.
- The rep comes from hip and knee travel, not ankle drift.
- The bottom/top dwell is long enough for the filtered `front_knee` signal to pass
  through the real rep state machine.

`MotionDemoTimelineTests.testLungeDemoTimelineKeepsFeetPlantedAndCountsOneRep`
guards this exact failure class.

## Motion data source options

The current generated frames are procedural fallback. `MotionDemoCompiler` chooses a known
exercise archetype from the active `ExerciseProgram` and emits synthetic
`PoseFrame` keyframes. Those frames are shaped like MediaPipe output, but they are
not imported from MediaPipe and they are not captured from a real trainer.

Better sources, in increasing implementation weight:

- **Reference-video traces:** record a trainer performing each exercise, run the
  same MediaPipe Pose worker over the video in deterministic `VIDEO` mode, smooth
  and normalize the result, then store the canonical `PoseFrame` timeline. This
  matches the app's live tracking contract but inherits MediaPipe's monocular pose
  limits.
- **Exercise datasets:** Fit3D publishes multi-view fitness sequences with GHUM
  and SMPL-X pose/shape parameters across repeated exercises; MM-Fit includes
  synchronized RGB-D video plus 2D/3D pose estimates for squats, push-ups, lunges,
  and other workouts; UI-PRMD includes Vicon and Kinect positions/angles for
  rehabilitation movements including deep squat, inline lunge, and side lunge.
- **General mocap libraries:** CMU Mocap and AMASS can provide natural human
  motion, but they need exercise selection, cleanup, retargeting, and license
  review before they become product demo clips.
- **First-party capture:** for production coaching, capture our own reference
  performers with the intended camera angles and coaching style. This gives us
  the cleanest product language and a known provenance chain.

For a rigged 3D avatar, the best long-term contract is not only `PoseFrame`.
`PoseFrame` is excellent for engine parity and MediaPipe-shaped tests, but a real
avatar wants joint rotations, foot contact events, center-of-mass control, and
retargeting metadata. The durable clip should therefore carry:

- a rig/animation clip for the avatar,
- a projected MediaPipe-33-style `PoseFrame` trace for engine/test parity,
- contact constraints such as planted left/right foot intervals,
- exercise semantics such as top, descent, bottom, ascent, and ready.

## Full contract

For future catalog/agent-generated exercises, add an explicit motion-demo block to the compile target:

```jsonc
{
  "trackability": "trackable_template",
  "archetype": "knee_flexion_side_view",
  "demo": {
    "view": "side",
    "tempo": {"down_ms": 700, "bottom_ms": 250, "up_ms": 700},
    "key_signals": [
      {"signal": "knee", "top": 170, "bottom": 90}
    ],
    "avatar_landmarks": ["shoulder", "hip", "knee", "ankle"]
  }
}
```

The compiler should emit three siblings from one source:

- `ExerciseProgram` for the tracker.
- `MotionDemoTimeline` for the avatar.
- Golden pose traces for replay tests and conformance.

Arbitrary `rep.down_when`, `rep.up_when`, and `form_rules` are not enough to reconstruct motion. They say what should be measured, not where every joint should be at each moment. The missing piece is the archetype/keyframe layer: squat, lunge, hinge, push, pull, hold, gait, etc.

## MediaPipe alignment

MediaPipe remains the observed-pose source. The app should preserve this boundary:

- Use `VIDEO` mode for deterministic replay and fixture generation.
- Use `LIVE_STREAM` only when the live async pipeline is ready.
- Decode MediaPipe landmarks into `PoseFrame`.
- Keep `primary.*` side locking stable for a set.
- Render avatar demo frames from the same `PoseFrame` shape so visual guide tests and engine tests share fixture vocabulary.

When world landmarks are fully carried through `PoseFrame`, the avatar should prefer world coordinates for depth and keep normalized image coordinates as fallback. Until then, the current demo compiler supplies synthetic `z` depth for the avatar renderer.
