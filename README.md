# CamiFit

An open-ended, **on-device** bodyweight-exercise coach for macOS. CamiFit watches you through the webcam, counts reps, checks your form against per-exercise rules, tracks sets, and gives live cues — all locally, offline.

The heart of CamiFit is a deterministic, timestamped **exercise engine** that runs an **Exercise-Program**: a JSON document with a small, sandboxed rule **DSL**. The same contract is hand-authored today and (later) authored dynamically by an agent — so adding a new exercise is data, not code.

```
PoseProvider (MediaPipe pose worker)  →  joint-angle signals  →  temporal filters
   →  validity gating  →  rep / hold / set state machines  →  form rules  →  cues + summary
```

## Layers

- **Layer 1 — On-device executor (current):** pose → signals → reps/form/sets, driven by hand-authored Exercise-Program JSON. Fully offline.
- **Layer 2 — Agent authoring (later):** a sidebar chat (Codex app-server + ChatGPT login) that generates new Exercise-Programs as validated JSON.
- **Layer 3 — Tracker (later):** saved routines, session history, progress over time.

## Status

Milestone **M1 — exercise engine + program contract (squat vertical)**. See:

- `docs/design/2026-06-03-camifit-exercise-engine-design.md` — full design.
- `GOAL.md` — active mission + constraints.
- `docs/briefs/` — current slice.

## Development

This repo uses a supervised **Codex executor / reviewer** workflow (see `executor-reviewer-pair-programming.md`):

```bash
scripts/run_codex_pair_cycle.sh --once     # one executor + reviewer cycle
scripts/audit_autonomous_workflow.sh       # check workflow state
```

The Swift engine builds with SwiftPM:

```bash
swift build
swift test
```
