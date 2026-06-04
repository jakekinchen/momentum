# GOAL

## Active Mission

Build **CamiFit**, an open-ended, on-device bodyweight-exercise coach for macOS. The foundation (Layer 1) is a deterministic, timestamped **exercise engine** that runs an **Exercise-Program** (JSON + a sandboxed rule DSL): pose landmarks → joint-angle signals → temporal filters → validity gating → rep/hold/set state machines → form rules → live cues + a post-set summary. The same JSON contract is later produced by an agent (Layer 2) and persisted/tracked over time (Layer 3).

The full, reviewed design is `docs/design/2026-06-03-camifit-exercise-engine-design.md`. The MediaPipe pose worker now lives on `main` at `pose_worker/` (Python, `VIDEO` mode, validated). The **north star** is a shipped macOS app: live camera → `MediaPipePoseProvider` (spawns `pose_worker.py`) → engine → live skeleton + rep/form HUD + exercise picker. Layer 2 (agent authoring via Codex app-server + ChatGPT login) and Layer 3 (session history/progress) come after. RF-DETR is intentionally **not** used — bodyweight reps/form/sets derive entirely from pose.

## Current Milestone

M3 - Integrated macOS app (productize). M2 (push-up, lunge, plank presets) complete — Swift gate green in reviewer decision 025.

## Current Slice

docs/briefs/035-app-mock-worker-ui-command.md

## Stop Conditions

- Stop or ESCALATE before any network model download (e.g. the MediaPipe model bundle) or `pip install` not explicitly authorized by the active brief. Slice 1 is pure Swift + JSON and must stay offline.
- Stop coaching-accuracy or performance claims until a golden landmark fixture proves exact rep counts AND no false reps during no-person / low-visibility intervals.
- Stop scope expansion into Layer 2 (agent / Codex / OpenAI) or Layer 3 (persistence) while M1 is active.
- The engine must reject invalid programs at load (unknown function, signal/filter DAG cycle, missing signal). A slice that weakens load-time validation is out of scope.
- **Loop↔human boundary:** the autonomous loop validates only what `swift test --disable-sandbox` / `pytest` can prove headlessly. Anything that needs a live camera or a running SwiftUI app (the macOS app target, camera capture, on-screen overlay) must be built as wireable, unit-tested pieces and then **ESCALATE** for human run-verification — never claim a live-app behavior works without that. Decoding/logic (e.g. `MediaPipePoseProvider` JSONL→`PoseFrame`) IS testable headlessly with recorded fixtures and stays in-loop.
- **pytest gate:** the `pose_worker/` pytest gate is **manager-verified** (the loop's sandbox lacks pytest; do NOT `pip install` in-loop). Slices that do not modify `pose_worker/` validate with `swift test --disable-sandbox` only and must not block on pytest. A slice that DOES modify `pose_worker/` should ESCALATE for a manager pytest run.

## Human Constraints

- The **Exercise-Program contract** is the single source of truth shared by hand-authored presets and (later) agent-authored programs. Do not fork its shape.
- The **DSL stays total and sandboxed**: no arbitrary code execution, no statements/loops/IO. Temporal behavior lives in `filters` and FSM config, never inside expressions.
- The **interpreter lives in Swift** (one evaluator); the Python pose worker is a pure, stateless, timestamped pose source behind a `PoseProvider` boundary.
- Require approval before paid cloud work, large downloads, destructive actions, or public release.
- Repo evidence beats chat memory: every slice leaves a brief, a session log (commands/outputs/files/validation/reachability), and a reviewer decision.
- **Validation convention (SwiftPM under the Codex sandbox):** validate with `swift build --disable-sandbox` and `swift test --disable-sandbox` using the **default in-repo `.build`**. Do NOT redirect `--scratch-path`/`--cache-path` outside the repo — Codex's `workspace-write` sandbox blocks external writes, and `--disable-sandbox` avoids SwiftPM's nested sandbox-exec. This lets the executor/reviewer self-validate without bypassing the Codex sandbox. Manager confirmed 8/8 tests green this way on 2026-06-03 (slice 001).
