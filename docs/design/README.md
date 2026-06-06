# Design Docs

Durable architecture docs live here. Prefer one canonical doc per topic, with older alternatives deleted or marked superseded.

## Canonical

| Doc | Status | Use for |
|---|---|---|
| [`2026-06-04-camifit-fitgraph-synthesis.md`](2026-06-04-camifit-fitgraph-synthesis.md) | Canonical | Three-repo synthesis: CamiFit hero app, FitGraph canonical oracle, Swift on-device KG runtime, candidate-assessment requirements floor. |
| [`2026-06-03-camifit-exercise-engine-design.md`](2026-06-03-camifit-exercise-engine-design.md) | Active design baseline | Exercise-Program JSON, pose-frame DSL, deterministic rep/form/hold engine. |
| [`2026-06-05-avatar-guide-motion-demo.md`](2026-06-05-avatar-guide-motion-demo.md) | Active feature design | Avatar guide toggle, `ExerciseProgram` -> `PoseFrame` demo timeline, and the future motion-archetype compiler contract. |
| [`2026-06-06-bodyweight-lunge-reference-pipeline.md`](2026-06-06-bodyweight-lunge-reference-pipeline.md) | Active feature design | Trainer-video -> MediaPipe -> normalized lunge guide trace pipeline for replacing the procedural Bodyweight Lunge demo. |

## Removed to avoid confusion

- `2026-06-04-three-repo-kg-camifit-synthesis-plan.md` was a competing synthesis draft. Its useful staged-implementation ideas were folded into the canonical CamiFit x FitGraph synthesis doc, then the file was removed.
