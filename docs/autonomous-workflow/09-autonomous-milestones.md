# Autonomous Milestones

This file defines invariant milestones for autonomous work on CamiFit.

Milestones are required outcomes, not detailed subtasks. The Executor and Reviewer choose the implementation slices needed to satisfy the next milestone. Authoritative design: `docs/design/2026-06-03-camifit-exercise-engine-design.md`.

## Overall Goal

A shipped macOS app where a user picks a bodyweight exercise and an offline engine — driven by an Exercise-Program (JSON + sandboxed DSL) — counts reps, checks form, tracks sets, and renders a live skeleton + rep/form HUD + post-set summary, fed by live camera through a MediaPipe pose worker. Proven on recorded landmark fixtures with exact rep counts and no false reps during no-person / low-visibility intervals.

## Milestone Rules

- Milestones are invariant outcomes, not task lists.
- Agents choose implementation slices needed to satisfy the next milestone.
- The Reviewer may not mark a milestone complete without running or recording its verification gate.
- The Manager challenges work that optimizes beyond the current milestone before the gate is satisfied.
- **Loop↔human boundary (see GOAL.md):** headlessly-testable work (engine, provider decode, presets, fixtures) is in-loop. Live-camera / running-SwiftUI-app behavior must be built as wireable, unit-tested pieces and then ESCALATE for human run-verification — never claim it works without that.

## M1 - Exercise engine + squat vertical  (≈80% done)

**Required outcome:** A squat Exercise-Program runs end-to-end through the Swift engine on recorded landmark fixtures: contract → DSL evaluation → filters → validity gating → rep state machine → form rules → cue/score output + engine trace.

**Done:** contract + load validation; sandboxed DSL evaluator; filter pipeline; validity gating; rep FSM (hysteresis + ROM + dwell + cooldown); set tracker; form-rule evaluator (timing + cue cooldown + weighted score); engine trace recorder/formatter; PoseFrame fixture harness + synthetic clean squat trace.

**Remaining slices:**
1. Low-visibility / no-person fixture proving NO false counted reps through invalid intervals (brief 018).
2. `MediaPipePoseProvider` (Swift): decode `pose_worker.py` JSONL → `PoseFrame`, bridging the worker's ordered 33-landmark array ↔ the engine's named-landmark representation. Headlessly testable against recorded JSONL fixtures.
3. Squat acceptance suite: ≥3 fixtures (clean / shallow / noisy-occluded) asserting exact rep counts, rep timestamps within tolerance, and no false reps in no-person/low-visibility stretches.

**Verification gate:**
```bash
swift test --disable-sandbox     # incl. squat acceptance suite
pytest pose_worker/tests          # worker green
```

## M2 - All bodyweight presets (push-up, lunge, plank)

**Required outcome:** Push-up, lunge, and plank ship as added Exercise-Program JSON + golden fixtures, with NO new engine architecture (proves the data-driven contract). Plank exercises the hold/timer path.

**Verification gate:** `swift test --disable-sandbox` with per-exercise fixture suites green (each: exact reps/hold, no false counts on invalid intervals).

## M3 - Integrated macOS app (productize)

**Required outcome:** A real SwiftUI `CamiFit` app target in this repo wires camera → `MediaPipePoseProvider` → engine → live skeleton overlay + rep/form HUD + exercise picker + post-set summary. This replaces the throwaway demo (forked from Cami in the rfdetr-mlx repo) with the real engine-backed app.

**Loop role:** build every headlessly-testable piece (view models, overlay geometry, HUD formatting, provider lifecycle, frame routing) with unit tests. The live camera + on-screen run is **human-verified** — executor ESCALATEs with a precise run checklist; it must not claim the live app works.

**Verification gate:** `swift test --disable-sandbox` green for all app logic; a human run-through of the packaged app (camera → live skeleton → counted reps → summary) recorded in a session log.

## M4 - Polish & layers (deferred)

- Replay/tuning debugger UI (plot signals/thresholds/phases/reps over a recorded trace).
- Audio cues (rep chime, fault tone) + richer post-set summary.
- Layer 2: agent authoring (`AuthoringProvider`, Codex app-server + ChatGPT login, sidebar chat) emitting validated programs.
- Layer 3: persistence — saved routines, session history, progress over time.
