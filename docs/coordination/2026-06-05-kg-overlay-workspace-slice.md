# 2026-06-05 KG Overlay Workspace Coordination

## Active Agent State

- Claude Code processes were observed with cwd `/Users/kelly/Developer/camifit`.
- This implementation slice is confined to
  `/Users/kelly/Developer/camifit-monorepo-synthesis`.
- FitGraph canonical source remains stopped by its own `<stop-orchestrator/>`
  sentinel; this slice does not resume FitGraph executor product work.

## Write Scope

This slice owns:

- `Sources/KGKit/*Workspace*`, `GraphOperation*`, `OverlayValidator`,
  `MemberOverlayState`, and `DecisionTransparency`.
- `Tests/KGKitTests/*Overlay*` and `DecisionTransparencyTests`.
- `contracts/graph-operation.schema.json`.
- `contracts/decision-explanation.schema.json`.

Other agents should avoid duplicating this exact overlay substrate unless they
are explicitly integrating or reviewing it. UI work can consume
`DecisionExplanation` and `GraphOperation` without editing canonical graph
artifact files.

## Coordination Notes

- Medical blocks remain hard for immediate recommendation use.
- User correction is modeled as an append-only state correction, not a session
  bypass: for example, `RetractMedicalConstraint` can make a stale knee-pain
  fact inactive, then safety must rerun before the previously excluded exercise
  becomes selectable.
- Overlay validators reject stale revisions and wrong base artifact hashes so
  concurrent agent writes fail closed instead of silently interleaving.

