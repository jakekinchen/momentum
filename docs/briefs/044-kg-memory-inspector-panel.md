# Brief 044 - KG Memory Inspector Panel

## Human Direction

Add a brain icon in the right-side menu/inspector that opens a user-accessible
memory list. The panel should show what CamiFit currently remembers about the
user from the mutable KG overlay, make the evidence and reasoning auditable, and
let the user correct or remove active memories without mutating the immutable KG
base artifact.

## Full Product Goal

CamiFit is a local-first fitness coach that can recommend a safe workout, turn
that recommendation into a runnable routine, watch the user perform it through
the camera, grade reps/holds/form offline, and then use the measured result to
improve the next recommendation. The product goal is not just "chat about
fitness"; it is a closed on-device loop:

```text
ask coach -> KG decides -> routine renders -> user performs -> engine grades ->
member KG updates -> next plan reflects real history
```

The user experience should feel like one product:

- The center of the app is the live/training surface: camera or recorded run,
  skeleton overlay, rep/hold/form HUD, routine progress, and session status.
- The right inspector has two cooperating modes:
  - `Coach`: a ChatGPT-backed Codex app-server chat that verbalizes bounded
    facts, answers questions, and can propose KG operations.
  - `Memories`: a brain-icon panel showing what CamiFit remembers, why it
    remembers it, what decisions those memories affected, and how to correct
    them.
- The KG is the decision brain: it resolves prompt text, checks safety,
  equipment, preferences, alternatives, and provenance. It emits receipts that
  the app can render.
- The pose engine is the execution body: it consumes validated
  `ExerciseProgram`s, computes signals from pose landmarks, counts reps/holds,
  evaluates form rules, and writes measured observations back into the member
  layer.
- Codex is the conversational surface: it may summarize fact cards or propose
  memory changes, but it does not decide safety, fabricate graph facts, or write
  the KG directly.

## How It Works

The complete product architecture has four cooperating layers:

1. **Canonical KG compiler / oracle.** FitGraph remains the Python build-time
   oracle. It imports the golden exercise/member data, validates graph integrity,
   compiles a signed/content-hashed graph artifact, and emits conformance
   vectors. Python never ships in the app runtime.
2. **Swift KGKit runtime.** CamiFit ships the frozen artifact and uses Swift
   KGKit for resolver, safety traversal, alternatives, workout generation,
   decision receipts, and fact cards. KGKit must match the Python oracle through
   conformance tests.
3. **CamiFitEngine runtime.** The engine is KG-agnostic. It runs pose frames
   through the deterministic signal DSL, filters, validity gates, rep/hold state
   machines, and form rules. A KG-selected exercise can start only if it has a
   runnable, validated program or is clearly labeled timer/manual or
   recommendation-only.
4. **CamiFit app shell.** The SwiftUI app owns the live session UI, Codex chat,
   regimen cards, memory inspector, Application Support graph workspace, and
   all user-visible correction/approval flows.

Runtime graph state has two layers:

- **Immutable base.** The signed artifact is bundled and copied to
  `Application Support/CamiFit/KnowledgeGraph/base/<sha>.kgart.json`. It is never
  edited in place.
- **Mutable member overlay.** User preferences, health constraints, equipment
  access, generated routine links, completed-session observations, corrections,
  and receipts live in append-only local files. The app builds the effective
  view from `base + overlay`.

The workout path should work like this:

1. The user asks for a workout in chat or chooses a guided flow.
2. The app collects prompt, time window, equipment, current profile memories,
   and any relevant fact cards.
3. KGKit resolves constraints and evaluates candidate exercises.
4. KGKit returns selected exercises, filtered exercises, alternatives, and
   `DecisionReceipt`s with graph paths and fingerprints.
5. The app shows a routine/regimen card with "Why this?" receipts and an
   "excluded because..." lane when useful.
6. Safe, runnable exercises compile into or reference validated
   `ExerciseProgram`s. Non-runnable items are labeled as timer/manual or
   recommendation-only.
7. During the workout, the pose engine grades the session locally.
8. Completed-session observations append to the member overlay without changing
   canonical safety edges.
9. Future recommendations and fact cards can read those observations.

The memory path should work like this:

1. The user or Codex chat turn surfaces a possible memory, such as "left knee
   pain" or "I have dumbbells now".
2. Codex may propose a structured `camifit-kg-operation`; the app validates it
   as a proposal, not active state.
3. The user approves, dismisses, corrects, or edits the proposal.
4. The app appends the validated operation to the overlay, stamps evidence, and
   reruns affected KG views.
5. The brain panel shows the active memory, its source, related receipts, and
   available correction/archive actions.
6. If the fact later changes, the user appends a retraction/correction instead
   of silently mutating the original history.

Non-negotiable product invariants:

- The LLM never decides eligibility or safety.
- Vector search never enforces safety.
- The base graph is immutable at runtime.
- Member-specific state is local, append-only, auditable, and correctable.
- Raw member KG/source text stays local by default.
- Receipts explain every recommendation, exclusion, substitution, and graph
  write.
- A hard medical block can be corrected if stale, but not bypassed as a casual
  session override.
- Real-world tests must prove behavior with realistic user facts, generated
  plans, receipts, corrections, and completed-session write-back.

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
- every user action, Codex proposal, or app-owned graph operation carries actor,
  timestamp, base artifact hash, precondition revision, source text/source span,
  and reason.

The same transparency model must also apply to recommendations. If CamiFit
recommends, filters, or substitutes an exercise in chat, the user should be able
to inspect the `DecisionReceipt` and see which parts came from the immutable base
KG and which parts came from their mutable on-device overlay.

The Codex app server is a verbalization and proposal surface, not the authority
that mutates the KG. The app owns the graph workspace, validation, consent, and
write application. Codex can suggest an operation or summarize approved local
facts; CamiFit decides whether that proposal becomes a validated overlay write.

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
- `CodexAppServerClient` currently starts Codex with `approvalPolicy: "never"`,
  `sandbox: "read-only"`, and a temporary cwd; it also refuses server-to-client
  requests. The memory plan must preserve that posture unless a future narrow
  app-owned proposal bridge is explicitly designed and tested.

## Phase 1 MVP

The first implementation is the smallest real memory inspector that proves the
overlay model in the shipped app. It should not attempt the whole product loop
in one slice.

Build only:

- add `KGKit` as a dependency of `CamiFitApp`;
- add an app-owned `KGMemoryStore`;
- prepare/load the Application Support `KGWorkspace`;
- add a right-inspector mode enum for `coach` and `memory`;
- add an icon-only brain button that opens the inspector in memory mode;
- render active and corrected health/safety memories from the overlay;
- show operation id, source text, actor, date, base artifact short hash, and
  overlay revision;
- support one correction action for active health/safety memories:
  append `RetractMedicalConstraint`;
- verify correction reruns the merged view and removes the health constraint from
  active memory state;
- keep the chat transcript alive when switching inspector modes.

Explicitly defer:

- Codex-proposed memory approval flows;
- user-visible receipt deep-links;
- base-vs-member plan comparison UI;
- fact-card grounding in coach turns;
- completed-session write-back;
- export/reset/local data controls;
- base artifact migration and corrupt-log quarantine;
- compaction/redaction;
- any user-visible CLI or shell tool.

The first slice is still real: it must read and write the local overlay through
`KGKit`, preserve the immutable base artifact, and pass app/model tests. It just
does not expose every future control surface at once.

## Phase 1 Implementation Checklist

Use this checklist as the executor handoff. If a step cannot be completed without
inventing behavior outside this list, stop and write the missing contract before
expanding scope.

1. Package boundary
   - Edit `Package.swift`.
   - Add `KGKit` to the `CamiFitApp` executable target dependencies.
   - Add `KGKit` to `CamiFitAppTests` only if the tests need to construct
     fixture workspaces directly.
   - Do not add any Python or canonical KG runtime dependency to `CamiFitApp`.

2. App-facing memory models
   - Add `Sources/CamiFitApp/KGMemoryModels.swift`.
   - Define `KGMemoryItem`, `KGMemoryCategory`, `KGMemoryStatus`, and a small
     `KGMemoryViewState`.
   - Keep these as SwiftUI-facing projections; do not bind views directly to raw
     `GraphOperation` JSON.

3. App-owned memory store
   - Add `Sources/CamiFitApp/KGMemoryStore.swift`.
   - Own `KGWorkspace.prepare(...)`, `GraphOperationLog`, `OverlayValidator`,
     and `MemberOverlayState` loading.
   - Expose published state: loading, loaded, empty, error, and current overlay
     revision/base short hash.
   - Implement `correctHealthMemory(operationID:reason:)` by appending
     `RetractMedicalConstraint` with the current base hash and precondition
     revision.
   - Reload after every successful append.
   - Fail closed on stale revision, base hash mismatch, or canonical mutation
     validation errors.

4. Inspector mode wiring
   - Edit `Sources/CamiFitApp/ContentView.swift`.
   - Add an inspector mode enum: `coach` and `memory`.
   - Keep the existing chat toggle behavior: if the inspector is hidden, the chat
     button opens it in `coach` mode and the brain button opens it in `memory`
     mode.
   - Preserve the existing `ChatViewModel` instance so switching modes does not
     clear the transcript.

5. Brain button and memory panel
   - Add `Sources/CamiFitApp/KGMemoryPanel.swift`.
   - Use an icon-only SF Symbol button, preferably `brain.head.profile`, with
     tooltip "Memories".
   - Render the Phase 1 panel header: "Memories", overlay revision, and base
     artifact short hash.
   - Render active/corrected health and safety memory rows from
     `KGMemoryStore`.
   - Show operation id, source text, actor, date, status, and a compact reason.
   - Provide the Phase 1 correction action only for active health/safety memory
     rows.
   - Show empty, loading, and error states. Corrupt-log quarantine can remain a
     follow-on item.

6. Phase 1 tests
   - Add `Tests/CamiFitAppTests/KGMemoryStoreTests.swift`.
   - Add `Tests/CamiFitAppTests/KGMemoryPanelModelTests.swift` or extend an
     existing app model test file if that matches local style better.
   - Keep tests model/store focused; no screenshot or live camera test is needed
     for this slice.

7. Required verification commands
   - Run `swift test --disable-sandbox --filter KGMemoryStoreTests`.
   - Run `swift test --disable-sandbox --filter KGMemoryPanelModelTests` if a
     separate model test file is added.
   - Run `swift test --disable-sandbox --filter KGKitTests`.
   - Run `swift test --disable-sandbox --filter CamiFitAppTests`.

Phase 1 is ready to close only when the executor can point to passing tests for:

- initial workspace load and projection;
- add medical constraint -> active memory projection;
- retract medical constraint -> corrected memory projection;
- stale revision/base hash failures;
- base artifact bytes unchanged;
- inspector mode switches without replacing the chat model;
- no user-visible CLI or shell command path.

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
- Sensitive source text should be visibly classified as local-only or shared
  with coach before it is included in any Codex prompt context.

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

Add an explicit proposal model for Codex-suggested mutations:

```swift
struct KGOperationProposal: Identifiable, Equatable {
    let id: String
    let proposedOperation: GraphOperation
    let sourceEvidence: KGSourceEvidenceItem
    let dryRunResult: String
    let requiresUserApproval: Bool
}
```

`KGOperationProposal` is not active graph state. It becomes active only after
the app validates and appends it through the same overlay path as a direct user
correction.

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
- Inject only user-approved, minimal fact-card summaries into coach turns as
  bounded context. The coach may summarize them, but if no fact card supports a
  claim, it must say the graph has no supporting fact.
- The Memory panel should show fact cards that are derived from active memories
  or session observations, and should deep-link to the supporting operations.
- Add quick prompts that route to fact-card queries rather than raw LLM answers,
  for example "What does Cami remember about my knee?" and "Why did this plan
  change?".

## Codex App-Server Boundary and Privacy Slice

Preserve the existing runtime safety posture while adding memory behavior:

- Do not let Codex execute shell commands or write Application Support files.
- Keep Codex turns on `approvalPolicy: "never"` and `sandbox: "read-only"` for
  the coach surface.
- Codex may emit a fenced `camifit-kg-operation` proposal or plain-language
  suggestion; the app parses it, dry-runs validation, and shows it for approval.
- The app-owned `KGMemoryStore`/overlay writer is the only writer to
  `KnowledgeGraph/overlays`.
- If a future app-server proposal bridge is added, it must be a narrow allowlist
  such as `propose_graph_operation` or `read_fact_card_summary`; it must not be
  a general bash/file-write bridge.
- Raw member KG, raw source spans, and health notes are local-only by default.
  Sending fact-card summaries to Codex requires an explicit product decision and
  a visible user control.
- Recommendation receipts and safety decisions are rendered locally from KGKit;
  they do not require sending the member overlay to Codex.

## Health Safety Semantics Slice

Medical memories need special handling:

- `review_after` should create a nudge to re-check a health fact, not silently
  remove or weaken it.
- Hard medical constraints never auto-expire into safe-to-use status. The user
  must explicitly correct the fact, and safety must rerun.
- The UI should distinguish "I told Cami this", "Cami measured this", and
  "Cami inferred this". Inferred health constraints should default to proposed,
  not active.
- Health-memory correction text should be stored as the source evidence for the
  retraction.
- The app should avoid giving medical advice; it can explain graph safety
  consequences and suggest consulting a professional for persistent or severe
  pain.

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

Codex is never the graph write path. It may verbalize approved fact cards or
propose a structured graph operation, but only app-owned code validates and
appends overlay operations.

- `KGMemoryStore` should be the app-owned writer for Phase 1.
- Future proposal handling should support dry-run validation that generates a
  candidate operation plus receipt without appending it.
- Codex-proposed health/safety operations should default to proposed until the
  user confirms in the Memory panel or the initiating chat turn clearly carries
  user consent.
- Every Codex proposal must include the source chat turn excerpt that justified
  it.
- The app should show proposed operations separately from active memories, with
  approve/dismiss controls.
- Concurrent writes should fail closed on revision mismatch and surface a
  reload/retry action rather than overwriting another app or user change.

## Contracts, Migration, and Local Data Controls Slice

Add durable contracts around the user-visible KG state:

- Add/validate JSON schemas for persisted recommendation receipts, comparison
  receipts, fact cards, memory projections, source evidence, operation proposals,
  and app-owned operation receipts.
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
- Add prompt-egress controls for coach grounding:
  - show which fact-card summaries may be sent to Codex;
  - keep raw source text local by default;
  - let the user disable memory-backed coach context while retaining local safety.

## Internal Overlay Writer And Test Harness

Do not expose a user-visible CLI for memories. User actions happen through the
CamiFit Memory panel and correction flows.

The implementation should use an app-owned writer surface, such as
`KGMemoryStore` backed by a small `KGOverlayWriter`, so app code and tests do not
write overlay JSON by hand. Any auxiliary harness should be debug/test-only, not
part of product acceptance, not shown to the user, and not available to the
Codex app-server process.

Required writer guarantees:

- never edit `base/<sha>.kgart.json`;
- validate base hash and overlay revision before every append;
- support dry-run/propose output without mutation;
- fail closed on stale revisions or canonical mutation attempts;
- write an action receipt under `receipts/` for every successful app-owned graph
  operation;
- include enough evidence for the user to understand why the memory exists;
- emit recommendation/comparison receipts that distinguish base-only results
  from merged member-overlay results;
- produce schema-valid receipts for every mutation, proposal, fact-card query,
  and plan comparison;
- never require the Codex process itself to have write access to the graph
  workspace.

## User Actions

Phase 1 implementation should support:

- Correct health/safety memory: append `RetractMedicalConstraint`.
- Copy operation id and evidence summary for debugging.

Avoid destructive physical deletion in the first slice. Label the primary
action as "Remove from active profile" or "Correct memory", not "erase
forever". A later privacy slice can add redaction/compaction for true local
deletion.

Follow-on user actions:

- Archive stale note/observation: append `ArchiveStaleObservation`.
- Add equipment access from a correction path: append `AddEquipmentAccess`.
- Open recommendation receipt from chat or a memory detail row.
- Correct a stale memory from an exclusion receipt, then rerun the plan.
- Approve or dismiss a Codex-proposed memory.
- Export local memory/receipt evidence.
- Reset local KG memories behind a confirmation flow.
- Toggle whether memory-backed fact-card summaries may be sent into Codex coach
  context.

## Full Test Plan

The Phase 1 close gate is the checklist above. The following test plan preserves
the broader product intent for follow-on slices after the MVP inspector is
working.

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
- Fact-card prompt export redacts raw local source text unless explicitly
  enabled.
- Workout observation write-back does not change safety receipts unless it
  creates a validated health/preference operation.
- Codex proposals do not become active memories until approved.
- Codex proposal parsing rejects malformed or unsupported
  `camifit-kg-operation` payloads.
- Corrupt overlay lines are quarantined and surfaced.
- Base artifact upgrade replay either succeeds with a migration receipt or
  quarantines incompatible operations.

Internal writer tests:

- `KGMemoryStore` loads the workspace and returns overlay revision plus active
  items.
- Adding a medical constraint through the app-owned writer followed by reload
  shows the active memory.
- Retracting a medical constraint through the app-owned writer followed by
  reload shows the item as corrected.
- Attempts to mutate canonical edges are rejected.
- Dry-run/proposal validation returns a valid proposed operation without
  appending to the overlay.
- Proposal validation rejects malformed proposals and canonical mutation
  attempts.
- Fact-card and export behavior, when added, return schema-valid local KG state.
- No test requires or exposes a user-visible shell command.

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
- Proposed Codex memories are visibly separate from approved active
  memories.
- Fact-card-backed chat answers show their source evidence; unsupported claims
  show an explicit no-support state.
- The UI shows which memory/fact-card summaries are local-only versus shared
  with the coach.
- Corrupt/migration-error states are visible and recoverable.

End-to-end behavioral test:

- Add left-knee pain through the store or Memory panel.
- Generate a lower-body workout and verify `Exercise:goblet_squat` is filtered.
- Correct the memory through the store or Memory panel.
- Regenerate and verify `Exercise:goblet_squat` is selectable again.
- Verify the comparison receipt says the base graph would allow the squat while
  the current member overlay filtered it, and that after correction the delta
  disappears.
- Run a completed-session write-back and verify memory/fact-card surfaces update
  while safety receipts remain unchanged.
- Have Codex propose a memory, approve it from the panel, and verify it
  then affects recommendations.
- Verify Codex can suggest a memory correction while the overlay remains
  unchanged until the app-owned approval path appends it.

## Acceptance Criteria

- A brain icon is visible in the right-side inspector controls.
- Clicking it opens the memory list without destroying the chat transcript.
- The list is backed by the KG overlay, not mock state.
- The user can see why each active memory exists, where it came from, and
  whether it affects safety/recommendations.
- Correcting/removing a health memory appends a validated operation rather than
  editing or deleting the base graph.
- No user-visible CLI or shell tool is required or exposed.

Follow-on acceptance:

- Chat recommendations and regimen cards expose deterministic `DecisionReceipt`
  explanations.
- The UI can show the original base-KG result and the mutable member-KG result
  side by side when they differ.
- Base-only recommendations are explanatory backups only; safety still reruns
  through the mutable member view before an exercise becomes selectable.
- Chat answers that mention user history or trends are grounded in fact cards
  with source nodes.
- Raw member KG/source text is not sent to Codex by default; shared coach context
  is bounded to approved fact-card summaries.
- Completed-session memories are stored separately from health/safety facts and
  cannot accidentally relax safety.
- Codex-created memories require an auditable source and either explicit consent
  or an approval step before activation.
- Local data export/reset and corrupt-log recovery paths are specified and
  tested.
- Tests cover model projection, operation writes, recommendation receipts,
  base-vs-member comparison, internal writer behavior, and the knee-pain
  correction loop.
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
- Giving the Codex app-server process direct file-write or shell-execution
  authority over Application Support.
