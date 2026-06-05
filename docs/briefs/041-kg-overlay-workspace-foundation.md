# Brief 041 - KG Overlay Workspace Foundation

## Human Direction

Implement the next development slice for the immutable KG base plus mutable
member overlay model. Preserve transparency for stale health facts such as knee
pain: a hard medical exclusion must explain the active stored fact, and the user
must have a clean correction path without deleting history or mutating the
canonical graph.

Also coordinate with active agents. Claude is working in
`/Users/kelly/Developer/camifit`; this slice writes only to the separate
`/Users/kelly/Developer/camifit-monorepo-synthesis` worktree.

## Scope

- Add `KGWorkspace` for `Application Support/CamiFit/KnowledgeGraph/` layout.
- Add append-only `GraphOperation` JSONL support for member overlay facts.
- Add `OverlayValidator` guardrails for base hash, revision, and canonical graph
  mutation rejection.
- Add `MergedGraphView` for base artifact plus accepted member overlay facts.
- Add `DecisionTransparency` recovery policies for excluded/correctable options.
- Add contract schemas for graph operations and decision explanations.

## Acceptance Criteria

- A content-addressed base artifact is copied once under `base/<sha>.kgart.json`.
- Member overlay operations append to `overlays/member/current.jsonl`.
- Active knee pain can filter a risky knee-loading exercise.
- A later correction can retract the active knee-pain fact, making the exercise
  selectable again after safety reruns.
- The base artifact bytes remain unchanged through overlay mutation.
- Stale revision, wrong base hash, and canonical mutation attempts fail closed.
- KGKit tests remain green.

