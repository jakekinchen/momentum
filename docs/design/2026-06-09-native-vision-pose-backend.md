# Native Vision Pose Backend

**Date:** 2026-06-09
**Status:** Implemented (default backend; MediaPipe worker kept as escape hatch)
**Scope:** Replace the PyInstaller-bundled Python MediaPipe sidecar with an
in-process Apple Vision body-pose backend for live tracking, removing the IPC
boundary, worker-path resolution fragility, model download, and ~250 MB helper
from the default path.

## Why now

The Python worker was always meant to be a swappable pose source — the original
engine design (2026-06-03, decision #12) defined the `PoseProvider` boundary
"to allow a future Apple Vision backend." The evidence that unlocked the swap:
**live tracking consumes only 12 of the 33 BlazePose landmarks** (left/right
shoulder, elbow, wrist, hip, knee, ankle — the union of every preset's
`required_landmarks`, signals, and form rules). Heel/foot-index and face
landmarks are used only by recorded guide traces, which are unaffected. Apple
Vision's `VNDetectHumanBodyPoseRequest` provides all 12 natively.

## Architecture

The camera pipeline is unchanged: `LiveCameraController` (AVFoundation) writes
JPEG frames at ~12 fps and `LiveSession` calls one predict per frame.

- `LivePoseBackend` (Sources/CamiFitApp/LivePoseBackend.swift) — protocol over
  the existing call shape: `start()`, `predict(imagePath:frameID:timestampMS:)
  -> PoseFrame?`, `stop()`, plus `startFailureDiagnostics` so the worker's
  python/script/model path hints still surface on launch failure.
- `VisionPoseBackend` (Sources/CamiFitApp/VisionPoseBackend.swift) — in-process
  implementation. Picks the highest-mean-confidence observation when Vision
  reports several (it frequently hallucinates 2–4 "people" in a one-person
  scene), flips Vision's bottom-left-origin normalized y into image space, and
  funnels points through the engine's shared mapping.
- `MediaPipePoseJSONLDecoder.livePoseFrame(...)` (CamiFitEngine) — the worker
  JSONL decode path's dot-renaming and primary-side locking, extracted to a
  public entry point both backends share, so naming and side-lock behavior are
  identical by construction (verified by a parity test that runs the same
  landmark values through both paths).
- `LivePoseBackendFactory` — `CAMIFIT_POSE_BACKEND=mediapipe` (or `python` /
  `worker`) restores the subprocess; anything else (including unset) uses
  Vision.

## Semantics deltas (accepted)

- **Partial poses drop the frame instead of flowing with low visibility.**
  MediaPipe regresses positions for out-of-frame joints and reports low
  visibility; the engine's 0.65 validity gate then rejects them. Vision reports
  confidence 0 with no usable location, so the backend returns "no pose."
  Functionally equivalent for tracking (neither path counts reps on such
  frames); the only UX delta is no skeleton overlay while the subject walks
  into frame.
- **z is 0.** Presets are `coordinate_space: image2d`; no live signal reads z.
- Heel/foot-index/face points are absent from live frames; the overlay simply
  draws fewer points. Guide traces keep full landmark sets.

## Verification

- Engine parity test (`LivePoseFrameMappingTests`): identical landmark values
  through the worker JSONL decode path and `livePoseFrame` produce identical
  frames; side-lock and missing-joint behavior pinned.
- Pure mapping tests (`VisionPoseMappingTests`): y-flip, naming, zero-confidence
  filtering, side-lock.
- Real-footage integration (`VisionPoseBackendCapturedFramesTests`, skips when
  no local captures): on 115 recorded live camera frames (360×640), A/B against
  the actual Python worker on the same frames showed **parity on every
  fully-framed frame** — MediaPipe engine-usable 12/23 sampled, Vision 13/23;
  the rest are walk-in/out frames with no subject or feet out of frame that
  neither backend can track. Mean primary-joint confidence 0.82, mean latency
  ~16 ms/frame in-process (worker: ~24 ms inference plus IPC and process
  overhead).

## What this removes from the default path

PyInstaller helper build (`scripts/build_pose_worker_helper.sh`), the ~250 MB
bundled binary, the `pose_landmarker_lite.task` download, Python interpreter
discovery (`LiveWorkerPaths` fallback cascade), subprocess health handshakes
(12–45 s timeouts), and per-frame IPC. All of it remains functional behind
`CAMIFIT_POSE_BACKEND=mediapipe` and continues to power the offline
motion-reference extraction pipeline, which still needs full 33-landmark
traces (heel/foot-index) for guide authoring.

## Follow-ups

- After the Vision backend soaks in real use, stop bundling the PyInstaller
  helper in the app package and let the mediapipe flag be a dev-repo-only path.
- Frame handoff still goes through JPEG temp files; a later slice can pass
  `CVPixelBuffer` straight from the capture output to Vision and delete the
  disk round-trip.
- The squat preset's `front_knee` signals are computed from both left/right
  sides for symmetry; if Vision confidence asymmetry ever shows up as noisy
  `*_symmetry` signals in practice, consider per-joint confidence smoothing.
