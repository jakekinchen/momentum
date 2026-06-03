# Executor Session 009 - Rep Cooldown Enforcement

**Date:** 2026-06-03  
**Role:** Executor  
**Active brief:** `docs/briefs/009-rep-cooldown-enforcement.md`

## Slice Summary

Implemented the smallest useful cooldown slice for the squat rep FSM:

- `RepStateMachine` now sets an explicit cooldown-until timestamp after a counted rep.
- Frames inside cooldown cannot start a new descent, continue an attempted second rep, or increment `repCount`.
- Cooldown state stays local to the rep FSM.
- `RepStateSnapshot` now exposes `cooldownRemainingMS` so tests and reviewers can prove the gate without inferring from private state.
- Existing dwell, ROM, no-false-rep, and invalid-frame behavior remains covered by the prior tests.

## Files Changed

- `Sources/CamiFitEngine/RepStateMachine.swift`
- `Tests/CamiFitEngineTests/RepStateMachineTests.swift`
- `docs/session-logs/009-executor-rep-cooldown-enforcement.md`

## Validation

Startup workflow audit:

```bash
scripts/audit_autonomous_workflow.sh
```

Result before implementation: clean.

Focused red check before production code:

```bash
swift test --disable-sandbox --filter RepStateMachineTests
```

Result: failed as expected because the tests referenced the new evidence field before implementation:

- `value of type 'RepStateSnapshot' has no member 'cooldownRemainingMS'`

Focused validation after implementation:

```bash
swift test --disable-sandbox --filter RepStateMachineTests
```

Result:

- 8 tests executed.
- 0 failures.

Broad validation:

```bash
swift build --disable-sandbox
swift test --disable-sandbox
```

Result:

- Build completed successfully.
- Full test suite executed 30 tests with 0 failures.

## Reachability Proof

The cooldown proof is reachable from the real product path used by the current Swift engine tests:

1. `ProductPathHarness` loads `Presets/bodyweight_squat.json`.
2. Synthetic timestamped frames are processed through `FrameSignalProcessor`.
3. Produced values are evaluated by `RepPredicateEvaluator`.
4. The configured phase-signal produced value is read from the loaded preset.
5. The resulting predicate and phase signal are fed into `RepStateMachine.update`.

The existing preset path still counts exactly one valid timed + ROM squat and now prints cooldown evidence:

```text
rep-state-timed-one-rep ... 16:ready:reps=1:counted=true:rom=82.1:cooldown=250 ...
```

The new cooldown test uses the same loaded-preset product path with a derived `RepConfig.cooldownMS = 5000` so the gate can be isolated from the real preset's shorter 250 ms cooldown. Evidence from the printed timeline:

```text
rep-state-cooldown ... 16:ready:reps=1:counted=true:rom=82.1:cooldown=5000 ... 55:ready:reps=2:counted=true:rom=82.1:cooldown=5000
```

All frames between those counted indices remain `counted=false` with `reps=1`, proving that the repeated threshold-crossing sequence inside cooldown did not double-count.

Invalid-frame behavior during cooldown was also exercised through the product path:

```text
invalid=phase=ready reps=1 counted=false cooldown=2400 invalid=phase signal knee invalid: ...
```

That invalid frame did not count and did not prevent the later valid after-cooldown sequence from counting exactly one additional rep.

## Flags For Reviewer

- Cooldown is intentionally local to `RepStateMachine`.
- This slice does not add set tracking, rest detection, hold evaluation, form rules, cue scoring, replay/debugger output, UI, audio, Python, MediaPipe, camera, network access, package dependencies, Layer 2, or Layer 3 behavior.
- Invalid phase-signal handling remains within the existing invalid-frame behavior; this slice does not implement full `validity.phase_signal_invalid_policy` semantics such as freeze-then-reset.
- The new test overrides only `cooldownMS` on the loaded preset's rep config to create a clear in-cooldown second attempt. The real preset path is still separately proven with its configured 250 ms cooldown.

## Next Suggested Slice

Add the smallest set-progress tracking layer over counted reps and `set.target_reps`, still offline and Swift-only. Keep form rules, cue scoring, UI, replay, and no-person/low-visibility gates out of that slice unless a new brief says otherwise.
