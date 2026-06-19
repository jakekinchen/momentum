# Design Docs

Durable architecture docs live here. Prefer one canonical doc per topic, with older alternatives deleted or marked superseded.

## Canonical

| Doc | Status | Use for |
|---|---|---|
| [`2026-06-04-momentum-fitgraph-synthesis.md`](2026-06-04-momentum-fitgraph-synthesis.md) | Canonical | Momentum hero app, FitGraph canonical oracle, Swift on-device KG runtime, candidate-assessment requirements floor. |
| [`../briefs/046-assignment-conformance-closeout.md`](../briefs/046-assignment-conformance-closeout.md) | Current closeout evidence | Assignment conformance implementation status, validation evidence, and residual limits. |
| [`../release/2026-06-06-conformance-release-closeout.md`](../release/2026-06-06-conformance-release-closeout.md) | Current release evidence | Local app artifact, GUI screenshots, signing state, and release validation commands. |
| [`2026-06-03-momentum-exercise-engine-design.md`](2026-06-03-momentum-exercise-engine-design.md) | Active design baseline | Exercise-Program JSON, pose-frame DSL, deterministic rep/form/hold engine. |
| [`2026-06-05-avatar-guide-motion-demo.md`](2026-06-05-avatar-guide-motion-demo.md) | Active feature design | Avatar guide toggle, `ExerciseProgram` -> `PoseFrame` demo timeline, and the future motion-archetype compiler contract. |
| [`2026-06-06-bodyweight-lunge-reference-pipeline.md`](2026-06-06-bodyweight-lunge-reference-pipeline.md) | Active feature design | Trainer-video -> MediaPipe -> normalized lunge guide trace pipeline for replacing the procedural Bodyweight Lunge demo. |
| [`2026-06-06-scalable-motion-reference-pipeline.md`](2026-06-06-scalable-motion-reference-pipeline.md) | Active design baseline | Scalable trainer-reference capture, motion profile registry, archetype normalizers, and coverage gates for every supported exercise. |

## Removed to avoid confusion

- The older three-repo KG synthesis draft was a competing plan. Its useful staged-implementation ideas were folded into the canonical Momentum x FitGraph synthesis doc, then the file was removed.
