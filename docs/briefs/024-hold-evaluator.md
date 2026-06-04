# Slice Brief 024 - HoldEvaluator (engine)

**Date:** 2026-06-03

## Objective

Add `HoldEvaluator` to the Swift engine: it executes a program's `hold` config (`HoldConfig { signal, inRange, targetSeconds }`) the way `RepStateMachine` executes `rep`. Each frame it evaluates the `inRange` predicate on the filtered hold `signal` and accumulates **time-in-range** from frame timestamps, exposing held seconds, in-range state, target-reached, and break/reset on exit or invalid input. This unblocks the plank preset (brief 025).

Pure Swift, offline, headlessly testable. Do not touch `pose_worker/`, the app, network, or downloads.

## Product / Project Value

Plank and every future hold/isometric exercise (wall-sit, dead-hang, side-plank) need a deterministic hold evaluator. It is the hold-path sibling of the rep state machine and completes the engine's exercise vocabulary (reps + holds).

## Scope

- `Sources/CamiFitEngine/HoldEvaluator.swift` — a pure, frame-fed evaluator mirroring `RepStateMachine`'s shape:
  - Input per frame: the produced signal table (filtered signals + validity from `FrameSignalProcessor`) + frame `timestampMS`.
  - Evaluate `hold.inRange` (a predicate expression, e.g. `hip_line between 160 and 185`) on the filtered `hold.signal`, reusing the existing predicate evaluation path (`RepPredicateEvaluator` / `Evaluator`) — do NOT add new DSL surface.
  - While in-range AND the signal is valid: accumulate `heldSeconds += dt` (dt from consecutive timestamps, clamped to a sane max to ignore gaps).
  - While out-of-range or invalid: do not accumulate; expose a break/reset (configurable: pause-and-resume vs reset — pick the simpler deterministic policy and document it).
  - Expose a per-frame snapshot: `heldSeconds`, `inRange: Bool`, `valid: Bool`, `targetReached: Bool` (heldSeconds >= targetSeconds), and a reason when not accumulating.
- Surface the hold result through the same engine path the acceptance suites use (extend `EngineTraceRecorder`/formatter or add a parallel hold trace) so a fixture test can assert held-seconds over a timestamped trace.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass (default in-repo `.build`); the existing 67 tests stay green.
- `Tests/CamiFitEngineTests/HoldEvaluatorTests.swift` with synthetic timestamped traces asserts:
  - held seconds accumulate while the signal stays in range;
  - no accumulation during out-of-range frames;
  - no accumulation during invalid / low-visibility frames (with a reason);
  - `targetReached` flips true exactly when held seconds cross `targetSeconds`.
- Reuses the existing predicate/DSL evaluation — no new DSL functions or operators.

## Expected Files

- `Sources/CamiFitEngine/HoldEvaluator.swift`
- possibly small additions to `EngineTraceRecorder.swift` / formatter for hold output
- `Tests/CamiFitEngineTests/HoldEvaluatorTests.swift`
- `Tests/CamiFitEngineTests/Fixtures/synthetic_plank_hold_trace.json` (a timestamped hold trace)
- `docs/session-logs/024-executor-hold-evaluator.md`

## Validation Commands

```bash
cd ~/Developer/camifit
swift build --disable-sandbox
swift test  --disable-sandbox
```

## Out Of Scope

- The plank preset JSON + acceptance suite (brief 025 — uses this evaluator).
- New DSL surface, `pose_worker/` changes, app, network, downloads.

## Stop Conditions

- ESCALATE if executing `hold` requires new DSL surface (it should not — `inRange` is an existing predicate expression).
- Keep the evaluator pure and frame-fed (no wall-clock; time comes from frame timestamps) so it is deterministic in tests.
