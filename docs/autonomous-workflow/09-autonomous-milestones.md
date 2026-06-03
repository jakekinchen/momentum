# Autonomous Milestones

This file defines invariant milestones for autonomous work on CamiFit.

Milestones are required outcomes, not detailed subtasks. The Executor and Reviewer choose the implementation slices needed to satisfy the next milestone. Authoritative design: `docs/design/2026-06-03-camifit-exercise-engine-design.md`.

## Overall Goal

A macOS app where a user picks a bodyweight exercise, and an offline engine — driven by an Exercise-Program (JSON + sandboxed DSL) — counts reps, checks form, tracks sets, and renders live cues + a post-set summary, proven on recorded landmark fixtures with exact rep counts and no false reps during no-person / low-visibility intervals.

## Milestone Rules

- Milestones are invariant outcomes, not task lists.
- Agents choose implementation slices needed to satisfy the next milestone.
- The Reviewer may not mark a milestone complete without running or recording its verification gate.
- The Manager challenges work that optimizes beyond the current milestone before the gate is satisfied.
- If a milestone gate proves wrong or incomplete, update this file.

## M1 - Exercise engine + program contract (squat vertical)

**Required outcome:** A squat Exercise-Program runs end-to-end through the Swift engine on recorded landmark fixtures: contract → DSL evaluation → filters → validity gating → rep state machine → form rules → cue/score output, with a replay debugger and a minimal live UI.

**Why this is invariant:** The contract + deterministic interpreter is the foundation every later layer (agent authoring, persistence) and every other exercise builds on.

**Indicative slices (Executor/Reviewer refine):**
1. Contract models + load-time structural validation (brief 001).
2. Sandboxed DSL parser + evaluator + identifier/function/DAG-cycle validation.
3. Filter pipeline (EMA/median, time-windowed) + validity gating (`SignalValue`, FSM invalid policy).
4. Rep state machine (hysteresis + ROM + dwell timing) + form evaluator (temporal cues + weighted score) + set tracker; hold evaluator for plank.
5. Python MediaPipe `VIDEO` pose worker behind a `PoseProvider`; timestamped frames; `num_poses=2`; normalized + world landmarks; fixture/replay playback; no temp-file-JPEG hot path.
6. Replay/tuning debugger + minimal live UI (skeleton, rep count, one cue, chime, summary).

**Verification gate:**

```bash
swift build
swift test
# Acceptance: >=3 squat fixtures (clean / shallow / noisy-occluded) assert exact rep counts,
# rep timestamps within tolerance windows, and no false reps during no-person/low-visibility intervals.
```

**Completion evidence:**

- Green `swift test` including the squat fixture acceptance suite.
- A replay-debugger artifact (recorded trace + plotted signals/thresholds/phases/reps).
- Session logs per slice with commands, outputs, files, validation, reachability.

## M2 - Remaining bodyweight presets (push-up, lunge, plank)

**Required outcome:** Push-up, lunge, and plank ship as added Exercise-Program JSON + golden fixtures, with no new engine architecture.

**Verification gate:** `swift test` with per-exercise fixture suites green.

## M3+ (deferred)

- Layer 2: agent authoring (`AuthoringProvider`, Codex app-server + ChatGPT login, sidebar chat) emitting validated programs.
- Layer 3: persistence — saved routines, session history, progress.
