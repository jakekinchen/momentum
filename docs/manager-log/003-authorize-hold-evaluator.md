# Manager Log 003 - Authorize HoldEvaluator (plank)

**Date:** 2026-06-03
**Role:** Manager / Guardian

## Context

Reviewer Decision 023 (`ESCALATE`, anchor 75): push-up (022) and lunge (023) presets landed cleanly as data + fixtures with no engine changes (67 tests green). But **plank** is a **hold** exercise (time-in-range), not rep-based. The contract already has `HoldConfig` (`signal`, `inRange`, `targetSeconds`) in `ExerciseProgram`/`ProgramLoader`, but **no `HoldEvaluator` executes it**. So plank cannot be a data-only preset — it needs a new engine component, which exceeds M2's "no new engine architecture" framing. Correct escalation.

## Decision

**Authorize a `HoldEvaluator` engine slice.** This is not scope creep — the design (§5.3 Holds, §7 interpreter) always specified a hold evaluator alongside the rep state machine; M2's "presets only" applied to the rep-based exercises (push-up/lunge), which reuse the existing rep FSM. Plank is the hold path the contract was built for.

M2 scope is refined to:
1. push-up preset ✅ (022)
2. lunge preset ✅ (023)
3. **`HoldEvaluator`** engine component (brief 024) — new, testable, pure/frame-fed like `RepStateMachine`.
4. **plank preset** (brief 025) — data + fixtures using the HoldEvaluator.

Current slice → `docs/briefs/024-hold-evaluator.md`. The HoldEvaluator is fully headlessly testable (`swift test`), so it stays in-loop.

## Next Action

Resume the loop on `docs/briefs/024-hold-evaluator.md`.
