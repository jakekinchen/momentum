# Slice Brief 021 - Squat Acceptance Suite

**Date:** 2026-06-03

## Objective

Add the first explicit squat acceptance suite for M1: run multiple checked-in pose fixtures through the full Swift engine and assert exact rep counts, counted-rep timestamps within tolerance, and no false counted reps during invalid no-person / low-visibility intervals.

Keep this headless and offline. Do not spawn Python, download a model, open a camera, run the SwiftUI app, or claim live app behavior.

## Product / Project Value

M1 is not complete until the squat program is proven against fixture-level acceptance criteria, not only isolated unit tests. This suite should become the durable gate that prevents regressions in counting, invalid-pose handling, and trace evidence as provider and app wiring continue.

## Scope

- Add a focused acceptance test file for the bodyweight squat preset, likely under `Tests/CamiFitEngineTests/`.
- Use checked-in fixtures only. Reuse existing fixtures where they fit:
  - clean squat fixture;
  - low-visibility fixture;
  - MediaPipe mixed no-pose fixture.
- Add small new synthetic fixture data only if the existing fixtures cannot cover the required acceptance cases.
- Cover at least three acceptance cases:
  - clean squat: exact final rep count and counted timestamp(s) within a small explicit tolerance;
  - shallow / insufficient-ROM squat: exact final rep count `0`;
  - invalid interval case: no false counted reps during low-visibility or no-pose timestamps, with invalid/missing-signal trace evidence.
- Run every case through the product path:
  - fixture decode / load;
  - `ProgramLoader.load(Presets/bodyweight_squat.json)`;
  - `EngineTraceRecorder.record(frames:)`;
  - `EngineTraceFormatter.format(_:)` for evidence.
- Keep expected counts and timestamp tolerances near the fixture definitions or in a small local test manifest so failures are easy to audit.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build`.
- Focused acceptance tests prove:
  - clean squat exact final rep count;
  - clean squat counted timestamp(s) within an explicit tolerance;
  - shallow / insufficient-ROM case does not count a rep;
  - low-visibility interval does not count a rep;
  - no-pose interval does not count a rep;
  - invalid intervals produce trace evidence naming missing/low-confidence landmarks;
  - formatted traces are reachable for failed-diagnosis evidence.
- Existing `PoseFrameFixtureTests` and `MediaPipePoseProviderTests` remain green.
- No fixture is large or binary.
- No Python process is spawned.
- No model download, camera access, SwiftUI app run, network dependency, Layer 2, or Layer 3 behavior is added.

## Expected Files

Likely files include:

- `Tests/CamiFitEngineTests/SquatAcceptanceTests.swift`
- Optional small fixture JSON/JSONL under `Tests/CamiFitEngineTests/Fixtures/`
- `docs/session-logs/021-executor-squat-acceptance-suite.md`

Names may change if the existing codebase has a clearer local structure. Keep the acceptance-suite boundary explicit.

## Validation Commands

```bash
cd /Users/kelly/Developer/camifit
swift build --disable-sandbox
swift test --disable-sandbox
```

Do not attempt `pip install`. If Python worker tests cannot run because `pytest` is unavailable, record that fact and continue with Swift validation.

## Evidence To Record

- `swift build --disable-sandbox` result.
- `swift test --disable-sandbox` test count and pass/fail.
- Acceptance summary for every case:
  - fixture name;
  - frame count;
  - expected rep count;
  - actual rep count;
  - expected counted timestamp(s);
  - actual counted timestamp(s);
  - invalid interval timestamps and false-count count.
- Trace excerpt for at least one invalid interval.
- Any fixture/tolerance choices made.

## Reachability / Demo Proof

Every acceptance case must run through the real bodyweight squat preset and `EngineTraceRecorder`. Do not prove acceptance only with direct `RepStateMachine`, `SignalEvaluator`, or hand-built assertion shortcuts.

## Out Of Scope

- Spawning `pose_worker.py`.
- Downloading or bundling a MediaPipe model.
- Camera capture.
- Live SwiftUI app wiring or visual overlay verification.
- Audio, transport, replay UI, plotting, Layer 2, Layer 3, or persistence.
- Process request/response framing for `pose_worker.py`.
- Push-up, lunge, plank, or other non-squat presets.
- Broad engine semantic changes unless an acceptance test exposes a specific bug that can be fixed narrowly inside the same slice.

## Stop Conditions

- ESCALATE before adding any network access, model download, `pip install`, camera code, live app run, or Python process spawning.
- ESCALATE if acceptance expectations require a human product judgment, such as changing the squat thresholds or deciding a borderline shallow rep should count.
- STOP if `swift test --disable-sandbox` cannot run with the default in-repo `.build`; record the exact failure.
- Do not mark M1 complete unless the acceptance suite and the milestone verification gate are explicitly satisfied or the remaining gate blocker is escalated.
