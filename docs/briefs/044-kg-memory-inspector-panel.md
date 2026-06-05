# Brief 044 - KG Memory Inspector Panel

## Human Direction

Add a brain icon in the right-side menu/inspector that opens a user-accessible
memory list. The panel should show what CamiFit currently remembers about the
user from the mutable KG overlay, make the evidence and reasoning auditable, and
let the user correct or remove active memories without mutating the immutable KG
base artifact.

## Product Principle

This is not a second preferences database. The panel is a friendly view over the
Application Support KG workspace:

```text
base/<sha>.kgart.json                  # immutable, content-addressed
overlays/member/current.jsonl          # append-only user/member operation log
receipts/                              # decision and action evidence
```

The user-facing word can be "Memory", but the implementation should preserve
the graph model:

- active memories are derived from accepted overlay operations;
- deleting from the active profile appends a retraction/archive operation;
- privacy-grade hard deletion is a later compaction/redaction flow, not the
  default correction path;
- every user or agent action carries actor, timestamp, base artifact hash,
  precondition revision, source text/source span, and reason.

## Current Code Context

- The right panel is currently a SwiftUI `.inspector` containing `ChatPanel` in
  `Sources/CamiFitApp/ContentView.swift`.
- `CamiFitApp` currently depends on `CamiFitEngine` only; it will need a
  package-boundary update to depend on `KGKit`.
- `KGKit` already provides `KGWorkspace`, `GraphOperationLog`,
  `OverlayValidator`, `MemberOverlayState`, `MergedGraphView`, and
  `DecisionTransparency`.
- The overlay bridge test already proves a knee-pain memory can exclude an
  exercise and a later retraction can make it selectable again.

## UX Shape

Use one right inspector with two modes:

- `Coach` mode: existing chat transcript and composer.
- `Memory` mode: new brain-icon panel showing active and archived KG memories.

Toolbar/header behavior:

- Keep the existing chat toggle semantics: if the inspector is hidden, clicking
  either chat or brain opens it.
- Add an icon-only brain button using an SF Symbol such as
  `brain.head.profile`, with tooltip "Memories".
- The active right-inspector mode should be visible through selected icon state,
  not a large text tab bar.

Memory panel layout:

- Header: brain icon, "Memories", overlay revision, base artifact short hash.
- Sections:
  - Active Health & Safety
  - Preferences & Equipment
  - Coach Notes
  - Archived / Corrected
- Each memory row shows title, status, source text, actor, date, review-after
  date if present, and a compact reason such as "Used by safety filtering".
- Selecting a row opens details with operation id, source spans, graph node ids,
  action history, and related decision receipts when available.

## Data Model Slice

Add an app-facing projection layer rather than binding SwiftUI directly to raw
`GraphOperation` JSON:

```swift
struct KGMemoryItem: Identifiable, Equatable {
    enum Category { case healthSafety, preference, equipment, coachNote, sessionObservation }
    enum Status { case active, corrected, archived }

    let id: String
    let title: String
    let category: Category
    let status: Status
    let sourceText: String
    let createdAt: String
    let actor: GraphOperationActor
    let operationID: String
    let replacesOperationID: String?
    let reviewAfter: String?
    let evidence: [String]
}
```

Add `KGMemoryStore` in the app target to:

- prepare/load the Application Support `KGWorkspace`;
- read `GraphOperationLog`;
- build `KGMemoryItem` values from `MemberOverlayState` and raw operations;
- append validated retraction/archive operations;
- expose `@Published` view state for SwiftUI.

## Agent Tooling Slice

Add a stable command-line tool so Codex/Claude agents do not write overlay JSON
by hand:

```bash
scripts/kg_overlay_tool.sh list --format json
scripts/kg_overlay_tool.sh add-medical-constraint --body-region left_knee --source-text "left knee pain"
scripts/kg_overlay_tool.sh retract --operation-id op-left-knee-pain-2026-06-05 --reason "It is better now"
scripts/kg_overlay_tool.sh archive --operation-id op-old-note --reason "No longer useful"
scripts/kg_overlay_tool.sh explain --exercise Exercise:goblet_squat
```

The shell wrapper should call a small Swift executable target, for example
`KGOverlayTool`, that depends on `KGKit`. Tool output must be JSON by default so
agent actions can be logged, tested, and inspected by the app.

Required tool guarantees:

- never edit `base/<sha>.kgart.json`;
- validate base hash and overlay revision before every append;
- fail closed on stale revisions or canonical mutation attempts;
- write an action receipt under `receipts/` for every successful agent action;
- include enough evidence for the user to understand why the memory exists.

## User Actions

First implementation should support:

- Correct health/safety memory: append `RetractMedicalConstraint`.
- Archive stale note/observation: append `ArchiveStaleObservation`.
- Add equipment access from a correction path: append `AddEquipmentAccess`.
- Copy/export operation evidence for debugging.

Avoid destructive physical deletion in the first slice. Label the primary
action as "Remove from active profile" or "Correct memory", not "erase
forever". A later privacy slice can add redaction/compaction for true local
deletion.

## Test Plan

Unit tests:

- `KGMemoryStore` maps add/retract operations into active/corrected memory
  items.
- Correcting an active knee-pain memory appends a valid
  `RetractMedicalConstraint` and removes it from active constraints.
- Archiving a stale observation leaves history readable but hides it from active
  sections.
- Stale revision and wrong base hash writes fail closed.
- The base artifact bytes are unchanged after memory actions.

CLI tests:

- `kg_overlay_tool list` returns valid JSON with overlay revision and active
  items.
- `kg_overlay_tool add-medical-constraint` followed by `list` shows the active
  memory.
- `kg_overlay_tool retract` followed by `list` shows the item as corrected.
- Tool attempts to mutate canonical edges are rejected.

UI/model tests:

- Right inspector mode defaults to coach chat.
- Brain button changes the mode to memory and opens the inspector.
- Memory rows expose action labels only when the operation type supports the
  action.

End-to-end behavioral test:

- Add left-knee pain through the tool/store.
- Generate a lower-body workout and verify `Exercise:goblet_squat` is filtered.
- Correct the memory through the store/tool.
- Regenerate and verify `Exercise:goblet_squat` is selectable again.

## Acceptance Criteria

- A brain icon is visible in the right-side inspector controls.
- Clicking it opens the memory list without destroying the chat transcript.
- The list is backed by the KG overlay, not mock state.
- The user can see why each active memory exists, where it came from, and
  whether it affects safety/recommendations.
- Correcting/removing a memory appends a validated operation rather than editing
  or deleting the base graph.
- Codex/Claude agents have a documented shell tool for the same operation path.
- Tests cover model projection, operation writes, CLI behavior, and the
  knee-pain correction loop.
- `swift test --disable-sandbox --filter KGKitTests` and relevant
  `CamiFitAppTests` pass.

## Non-Goals

- Cloud sync or multi-member accounts.
- LLM-driven eligibility decisions.
- Vector search for safety enforcement.
- Physical deletion/redaction of historical operations.
- A full graph browser for canonical exercise/anatomy nodes.
