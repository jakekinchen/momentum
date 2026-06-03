# Slice Brief 002 - Sandboxed DSL evaluator + calibration signal-reference validation

**Date:** 2026-06-03

## Objective

Add the **runtime evaluation** half of the DSL: a sandboxed parser + evaluator that, given a `PoseFrame`-like landmark table and engine state vars, computes each program's `signals` to a `SignalValue` (`valid(value, confidence)` | `invalid(reason)`). Slice 001 already validates the *contract* and rejects unknown functions / dependency cycles at load; this slice makes those expressions actually **evaluate**, deterministically and safely. Also close the reviewer's load-time gap: validate `setup.calibration.*.signals` references against produced signal/filter names.

Still **pure Swift, offline** — no MediaPipe, no Python worker, no network. Landmark inputs come from in-test synthetic tables (a tiny `PoseFrame` value type), not a camera.

## Product / Project Value

The evaluator is the core of the engine: every later component (filters, validity gate, rep FSM, form rules) consumes evaluated signals. Getting a total, sandboxed evaluator with explicit validity semantics right now unblocks all of M1 and guarantees agent-authored programs (Layer 2) can never execute outside the allowlist.

## Scope (this slice only)

- A `PoseFrame` value type (subset sufficient for evaluation): `timestampMS`, image size, and 33 named landmarks each with `x, y, z, visibility, presence`, addressable as `left.<name>` / `right.<name>` / `primary.<name>`. `primary` is provided by the caller (locked-side simulation); no frame-by-frame side selection inside the evaluator.
- A recursive-descent (Pratt) **expression parser → AST** and an **evaluator** over `{ landmarks, signals-so-far, state vars (phase, rep_count, time_in_phase_ms) }`.
- Operators: `+ - * /` (safe divide), comparisons, `and/or/not`, `in [..]`, `between a and b`. Functions: `angle`, `angle_to_vertical`, `angle_to_horizontal`, `signed_angle`, `distance`, `midpoint`, `ratio`, `abs`, `min`, `max`.
- `SignalValue` semantics: a signal is `invalid(reason)` if any landmark it needs is below `validity.min_signal_confidence` (use `visibility`/`presence`), or arithmetic is undefined (e.g. divide-by-zero, degenerate angle). Signals evaluate in dependency order (DAG from slice 001).
- **Load-time addition:** reject a program whose `setup.calibration.*.signals` (or any setup-referenced signal) names a value not produced by `signals`/`filters`. Add a typed error case.

## Acceptance Criteria

- `swift build --disable-sandbox` and `swift test --disable-sandbox` pass using the default in-repo `.build` (per GOAL validation convention).
- For the squat preset on a synthetic standing pose, `knee_*` and `torso_raw` evaluate to expected angle values within a tolerance; `knee_symmetry` equals `abs(knee_left - knee_right)`.
- Low-visibility landmark → dependent signal is `invalid` with a reason naming the offending landmark; valid landmarks still evaluate.
- Each allowlisted function has a unit test on known inputs (e.g. a right angle ≈ 90°, `midpoint` of two points, `signed_angle` sign).
- Divide-by-zero / degenerate inputs return `invalid`, never crash or NaN-propagate silently.
- A program referencing an undefined signal in `setup.calibration` is rejected **at load** with the new typed error (test with a fixture).
- Evaluation is deterministic: same frame + state → same `SignalValue`s.

## Expected Files

- `Sources/CamiFitEngine/Expression/Lexer.swift`, `Parser.swift`, `AST.swift`, `Evaluator.swift` (names at executor's discretion)
- `Sources/CamiFitEngine/PoseFrame.swift`
- Extend `Sources/CamiFitEngine/ProgramLoader.swift` (calibration signal-reference validation + new error case)
- `Tests/CamiFitEngineTests/EvaluatorTests.swift`
- `Tests/CamiFitEngineTests/Fixtures/invalid_calibration_signal_ref.json`
- `docs/session-logs/002-executor-dsl-evaluator-and-calibration-validation.md`

## Validation Commands

```bash
cd ~/Developer/camifit
swift build --disable-sandbox
swift test  --disable-sandbox
```

## Evidence To Record

- `swift test --disable-sandbox` count + pass/fail (must run to completion this time).
- Evaluated signal values for the synthetic standing-squat pose.
- The invalid-visibility case reason string.
- The new calibration-reference rejection error.

## Reachability / Demo Proof

Evaluate the real `Presets/bodyweight_squat.json` `signals` against a committed synthetic `PoseFrame` and print the resulting `SignalValue` table — proving end-to-end load → evaluate from a real product path.

## Out Of Scope (later slices)

- Filter runtime (EMA/median time windows), the validity FSM policy timing, rep/hold/set state machines (slice 003+).
- Python MediaPipe pose worker / `PoseProvider` / transport (slice 005+).
- UI, overlay, audio, replay debugger.
- Any network / model download / `pip` / remote dependency.

## Stop Conditions

- ESCALATE before adding any remote dependency, network access, or model download.
- If `swift test --disable-sandbox` still cannot run with the default in-repo `.build`, STOP and report the exact failure (do not redirect scratch outside the repo).
- Keep the DSL total: no statements, loops, assignment, IO, or non-allowlisted calls. If an expression seems to need them, ESCALATE rather than widening the language.
