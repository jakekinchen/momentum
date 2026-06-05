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
- every user or Codex/tool action carries actor, timestamp, base artifact hash,
  precondition revision, source text/source span, and reason.

The same transparency model must also apply to recommendations. If CamiFit
recommends, filters, or substitutes an exercise in chat, the user should be able
to inspect the `DecisionReceipt` and see which parts came from the immutable base
KG and which parts came from their mutable on-device overlay.

The panel also needs to respect the larger decide -> author -> run loop:

- recommendations come from deterministic KG receipts;
- generated routines must indicate whether each exercise is runnable by the
  current pose engine or recommendation-only;
- completed sessions eventually write measured observations back into a separate
  member overlay partition;
- chat answers about the user must be grounded in deterministic fact cards, not
  free-form memory claims invented by the coach.

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
- `WorkoutGenerator` currently returns selected/filtered exercise summaries and
  alternatives, but it does not yet expose full receipt cards to the chat UI.
- `DecisionReceipt` and `DecisionTransparency` already contain the ingredients
  needed for user-visible "why this recommendation?" cards.
- The canonical synthesis expects fact cards from member retrieval, session
  write-back into an `ExercisePerformance`/`WorkoutSession` partition, and
  receipt/fact-card schemas validated through `contracts/`.

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
- The panel must have empty, loading, error, and corrupt-log states. Corrupt
  overlay lines should be quarantined and shown as recoverable local-data issues,
  not silently ignored.

Chat receipt layout:

- Recommended exercises should render an inline "Why this?" affordance in the
  coach chat and regimen cards.
- The receipt detail should show:
  - selected/filtered/downranked decision;
  - primary reason and severity;
  - graph paths used as evidence;
  - base artifact short hash and overlay revision;
  - relevant active memory operations, if any;
  - execution availability: runnable now, timer/manual, or recommendation-only;
  - whether an excluded option is correctable, session-overrideable, or blocked.
- Filtered exercises should still be visible in a secondary "excluded because"
  lane when useful, especially when the exclusion is caused by a mutable member
  fact the user may want to correct.

Base-vs-member comparison layout:

- When the mutable member view changes the recommendation set, show the delta in
  plain language:
  - "Base KG result" = what the immutable base artifact would recommend without
    member overlay constraints.
  - "Your current profile result" = what the merged on-device KG recommends.
  - "Changed because" = the active overlay memory or preference that caused the
    difference.
- The base result is backup/explanatory, not a bypass. A medical hard block from
  the member overlay must never become a one-click "use anyway" action; it can
  only offer a correction path such as "My knee pain is resolved".

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

Add a receipt projection layer for chat and regimen cards:

```swift
struct KGRecommendationReceiptItem: Identifiable, Equatable {
    let id: String
    let exerciseID: String
    let exerciseTitle: String
    let decision: String
    let primaryReason: String
    let severity: String
    let recoveryPolicy: ExclusionRecoveryPolicy
    let graphPaths: [String]
    let baseArtifactShortHash: String
    let overlayRevision: Int
    let relatedMemoryOperationIDs: [String]
    let executionAvailability: String
}
```

Add a plan-comparison projection so the UI can explain base-vs-member deltas:

```swift
struct KGPlanComparison: Equatable {
    let basePlan: WorkoutPlan
    let memberPlan: WorkoutPlan
    let overlayAddedFilters: [KGRecommendationReceiptItem]
    let overlayUnlockedItems: [KGRecommendationReceiptItem]
}
```

The comparison should be generated by running the deterministic generator twice:

1. Base view: immutable artifact with no member overlay constraints.
2. Member view: `MergedGraphView` with `activeResolvedConstraints`.

The app should persist or display both receipt sets with explicit labels so the
user can distinguish canonical graph behavior from personal overlay behavior.

Add a source/evidence projection for operations and receipts:

```swift
struct KGSourceEvidenceItem: Identifiable, Equatable {
    let id: String
    let sourceSpanID: String
    let sourceKind: String
    let summary: String
    let excerpt: String
    let createdAt: String
}
```

Source span ids in `GraphOperation` should point to retrievable local evidence
when possible: chat turn excerpt, user correction text, session summary, or
tool invocation receipt.

## Recommendation Receipt Slice

Extend the workout/chat path so every KG-backed recommendation can surface its
receipt:

- Extend `WorkoutPlan` or add a companion receipt bundle containing full
  `DecisionReceipt`s for selected and filtered candidates.
- Attach `DecisionTransparency.explain(...)` output to filtered or substituted
  exercises.
- Render receipt cards under chat recommendations and generated regimen cards.
- Store decision/action receipts under `KnowledgeGraph/receipts/` with stable
  ids, base artifact hash, overlay revision, prompt text, selected exercise ids,
  filtered exercise ids, alternatives, and graph paths.
- Let the Memory panel deep-link from a memory row to any recommendation receipt
  that used that memory.
- Keep the LLM role verbal only: the receipt comes from `KGKit`, not from the
  coach inventing reasons.

## Base-vs-Mutable KG Slice

Implement an explicit comparison path between the original KG and the mutable
on-device view:

- Build a base-only plan from the copied immutable artifact with an empty member
  overlay.
- Build the normal member plan from `MergedGraphView`.
- Diff selected, filtered, and alternative exercises.
- Label overlay-only changes clearly, for example:
  - "Excluded by your active left-knee pain memory."
  - "Available in the base graph, but filtered by your current profile."
  - "This memory can be corrected if it is stale."
- If the member plan has too few usable results, show safe alternatives first,
  then optionally show base-only exclusions as explainable backups that require
  correcting the stored fact before use.
- Persist the comparison receipt so future app/tool actions and the user can
  audit why a recommendation changed over time.

## Fact Card and Coach Grounding Slice

Add the missing bridge between memories and chat grounding:

- Port or wrap the deterministic member-retrieval queries from the canonical KG
  layer into Swift, returning fact cards such as adherence trend, recent
  sessions, sleep/recovery if present, goals/preferences, and coach brief.
- Every fact card must carry `source_nodes`/source operation ids and a confidence
  marker such as `deterministic`.
- Inject fact cards into coach turns as bounded context. The coach may summarize
  them, but if no fact card supports a claim, it must say the graph has no
  supporting fact.
- The Memory panel should show fact cards that are derived from active memories
  or session observations, and should deep-link to the supporting operations.
- Add quick prompts that route to fact-card queries rather than raw LLM answers,
  for example "What does Cami remember about my knee?" and "Why did this plan
  change?".

## Execution Write-Back Slice

The memory panel should be prepared for measured workout memories, not just chat
preferences:

- Add a separate append-only partition for `WorkoutSession` and
  `ExercisePerformance` observations rather than mixing noisy pose-derived
  measurements with safety-critical health facts.
- A completed set/session should write measured reps, hold duration, form score,
  selected cues, and source trace ids as observation operations.
- Fact cards may read these observations, but safety traversal must remain
  unchanged unless a validated health/preference operation explicitly changes
  constraints.
- Add an isolation test: writing a workout observation must not change safety
  receipts for the same prompt/equipment/profile.
- The Memory panel should label measured observations differently from user
  claims, for example "Measured by camera" vs "Told to coach".

## Codex App-Server Authority and Approval Slice

The runtime write path is the Codex app server plus local overlay tooling. It
needs a safe dynamic-write path:

- The overlay tool should support `--dry-run` and `propose` modes that generate
  a candidate operation plus receipt without appending it.
- Codex-authored health/safety operations should default to proposed until the
  user confirms in the Memory panel or the initiating chat turn clearly carries
  user consent.
- Every Codex/tool operation must include the source chat turn or tool transcript
  excerpt that justified it.
- The app should show proposed operations separately from active memories, with
  approve/dismiss controls.
- Concurrent writes should fail closed on revision mismatch and surface a
  reload/retry action rather than overwriting another app/tool or user change.

## Contracts, Migration, and Local Data Controls Slice

Add durable contracts around the user-visible KG state:

- Add/validate JSON schemas for persisted recommendation receipts, comparison
  receipts, fact cards, memory projections, source evidence, and tool receipts.
- Stamp every persisted local record with schema version, base artifact hash,
  overlay revision, and app build/runtime version.
- Add migration behavior for base artifact upgrades: existing overlay operations
  must either replay cleanly against the new base hash through an explicit
  migration receipt, or be quarantined with a user-visible explanation.
- Add log-compaction support that can produce signed local snapshots while
  preserving active/corrected/archive semantics.
- Add local data controls:
  - export memories and receipts as JSON;
  - reset all local KG memories after confirmation;
  - compact/redact specific historical source text in a later privacy-grade
    deletion flow while preserving non-sensitive tombstones needed for audit.

## Codex Overlay Tooling Slice

Add a stable command-line tool so the Codex app server and local automation do
not write overlay JSON by hand:

```bash
scripts/kg_overlay_tool.sh list --format json
scripts/kg_overlay_tool.sh add-medical-constraint --body-region left_knee --source-text "left knee pain"
scripts/kg_overlay_tool.sh retract --operation-id op-left-knee-pain-2026-06-05 --reason "It is better now"
scripts/kg_overlay_tool.sh archive --operation-id op-old-note --reason "No longer useful"
scripts/kg_overlay_tool.sh explain --exercise Exercise:goblet_squat
scripts/kg_overlay_tool.sh compare-plan --prompt "lower body" --minutes 40 --equipment dumbbell,kettlebell
scripts/kg_overlay_tool.sh propose add-medical-constraint --body-region left_knee --source-text "left knee pain"
scripts/kg_overlay_tool.sh fact-cards --query adherence_trend
scripts/kg_overlay_tool.sh export --format json
```

The shell wrapper should call a small Swift executable target, for example
`KGOverlayTool`, that depends on `KGKit`. Tool output must be JSON by default so
Codex/tool actions can be logged, tested, and inspected by the app.

Required tool guarantees:

- never edit `base/<sha>.kgart.json`;
- validate base hash and overlay revision before every append;
- support dry-run/propose output without mutation;
- fail closed on stale revisions or canonical mutation attempts;
- write an action receipt under `receipts/` for every successful Codex/tool
  action;
- include enough evidence for the user to understand why the memory exists;
- emit recommendation/comparison receipts that distinguish base-only results
  from merged member-overlay results;
- produce schema-valid receipts for every mutation, proposal, fact-card query,
  and plan comparison.

## User Actions

First implementation should support:

- Correct health/safety memory: append `RetractMedicalConstraint`.
- Archive stale note/observation: append `ArchiveStaleObservation`.
- Add equipment access from a correction path: append `AddEquipmentAccess`.
- Copy/export operation evidence for debugging.
- Open recommendation receipt from chat or a memory detail row.
- Correct a stale memory from an exclusion receipt, then rerun the plan.
- Approve or dismiss a Codex/tool-proposed memory.
- Export local memory/receipt evidence.
- Reset local KG memories behind a confirmation flow.

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
- `KGPlanComparison` labels exercises filtered only by the member overlay.
- Recommendation receipt projection preserves graph paths, reason codes, base
  artifact hash, overlay revision, and related memory operation ids.
- Fact-card projection refuses unsupported claims and preserves source nodes.
- Workout observation write-back does not change safety receipts unless it
  creates a validated health/preference operation.
- Codex/tool proposals do not become active memories until approved.
- Corrupt overlay lines are quarantined and surfaced.
- Base artifact upgrade replay either succeeds with a migration receipt or
  quarantines incompatible operations.

CLI tests:

- `kg_overlay_tool list` returns valid JSON with overlay revision and active
  items.
- `kg_overlay_tool add-medical-constraint` followed by `list` shows the active
  memory.
- `kg_overlay_tool retract` followed by `list` shows the item as corrected.
- Tool attempts to mutate canonical edges are rejected.
- `kg_overlay_tool explain` returns the same decision reason as `KGKit`.
- `kg_overlay_tool compare-plan` returns separate base and member results plus
  overlay-caused deltas.
- `kg_overlay_tool propose ...` returns a valid proposed operation without
  appending to the overlay.
- `kg_overlay_tool fact-cards` returns deterministic facts with source nodes.
- `kg_overlay_tool export` returns schema-valid local KG state.

UI/model tests:

- Right inspector mode defaults to coach chat.
- Brain button changes the mode to memory and opens the inspector.
- Memory rows expose action labels only when the operation type supports the
  action.
- Chat recommendation cards expose a "Why this?" receipt.
- Filtered/excluded cards show correction actions only for supported recovery
  policies.
- Base-only backup options are visually secondary to safe member-plan results
  and cannot bypass medical hard blocks.
- Proposed Codex/tool memories are visibly separate from approved active
  memories.
- Fact-card-backed chat answers show their source evidence; unsupported claims
  show an explicit no-support state.
- Corrupt/migration-error states are visible and recoverable.

End-to-end behavioral test:

- Add left-knee pain through the tool/store.
- Generate a lower-body workout and verify `Exercise:goblet_squat` is filtered.
- Correct the memory through the store/tool.
- Regenerate and verify `Exercise:goblet_squat` is selectable again.
- Verify the comparison receipt says the base graph would allow the squat while
  the current member overlay filtered it, and that after correction the delta
  disappears.
- Run a completed-session write-back and verify memory/fact-card surfaces update
  while safety receipts remain unchanged.
- Have Codex/tooling propose a memory, approve it from the panel, and verify it
  then affects recommendations.

## Acceptance Criteria

- A brain icon is visible in the right-side inspector controls.
- Clicking it opens the memory list without destroying the chat transcript.
- The list is backed by the KG overlay, not mock state.
- The user can see why each active memory exists, where it came from, and
  whether it affects safety/recommendations.
- Chat recommendations and regimen cards expose deterministic `DecisionReceipt`
  explanations.
- The UI can show the original base-KG result and the mutable member-KG result
  side by side when they differ.
- Base-only recommendations are explanatory backups only; safety still reruns
  through the mutable member view before an exercise becomes selectable.
- Chat answers that mention user history or trends are grounded in fact cards
  with source nodes.
- Completed-session memories are stored separately from health/safety facts and
  cannot accidentally relax safety.
- Codex/tool-created memories require an auditable source and either explicit
  consent or an approval step before activation.
- Local data export/reset and corrupt-log recovery paths are specified and
  tested.
- Correcting/removing a memory appends a validated operation rather than editing
  or deleting the base graph.
- The Codex app server and local automation have a documented shell tool for the
  same operation path.
- Tests cover model projection, operation writes, recommendation receipts,
  base-vs-member comparison, CLI behavior, and the knee-pain correction loop.
- `swift test --disable-sandbox --filter KGKitTests` and relevant
  `CamiFitAppTests` pass.

## Non-Goals

- Cloud sync or multi-member accounts.
- LLM-driven eligibility decisions.
- Vector search for safety enforcement.
- Physical deletion/redaction of historical operations.
- A full graph browser for canonical exercise/anatomy nodes.
- Letting the coach fabricate explanation text that is not grounded in a
  `DecisionReceipt`.
- Cloud/device sync conflict resolution.
- Full privacy-grade source-text redaction in the first implementation slice.
