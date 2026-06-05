# 045 Executor - KG Memory Inspector UI Wiring

## Slice

Wired the Phase 1 KG memory store into the right inspector with a coach/memory
mode switch, an icon-only brain button, and a minimal `KGMemoryPanel` that uses
the existing app-owned `KGMemoryStore`.

No Codex proposal bridge, receipt deep-links, base-vs-member plan comparison,
Python dependency, model download, `pose_worker/` change, or user-visible CLI
path was added.

## Files Changed

- `Sources/CamiFitApp/ContentView.swift`
  - Added `AppInspectorMode` and `AppInspectorState`.
  - Replaced the chat-only inspector boolean with inspector mode state.
  - Preserved the existing `@StateObject private var chat = ChatViewModel()`.
  - Added `@StateObject private var memoryStore = KGMemoryStore()`.
  - Added an icon-only `brain.head.profile` toolbar button with help text
    `Memories`.
  - Routed inspector content to `ChatPanel` for coach mode and
    `KGMemoryPanel(store:)` for memory mode.
  - Calls `memoryStore.load()` from the app `onAppear`.
- `Sources/CamiFitApp/KGMemoryPanel.swift`
  - Added loading, empty, error, and loaded states.
  - Added header with `Memories`, overlay revision, and base short hash.
  - Renders active and corrected health/safety rows.
  - Shows operation id, source text, actor, date, status, compact reason, and
    evidence.
  - Exposes one active-row action: `Mark Resolved`, which calls
    `KGMemoryStore.correctHealthMemory(operationID:reason:)`.
- `Tests/CamiFitAppTests/KGMemoryPanelModelTests.swift`
  - Added headless coverage for the inspector mode state:
    hidden coach inspector -> memory mode, memory mode -> coach mode, and
    value-only state that does not own or replace the chat model.
- `docs/session-logs/045-executor-kg-memory-inspector-ui-wiring.md`
  - This log.

## Validation

```bash
swift test --disable-sandbox --filter KGMemoryPanelModelTests
# passed: 2 tests, 0 failures
```

```bash
swift test --disable-sandbox --filter KGMemoryStoreTests
# passed: 4 tests, 0 failures
```

```bash
swift test --disable-sandbox --filter CamiFitAppTests
# passed: 60 tests, 0 failures
```

```bash
swift build --disable-sandbox
# passed
```

```bash
git diff --check
# passed
```

```bash
scripts/audit_autonomous_workflow.sh
# workflow audit clean
```

Note: `swift build --disable-sandbox` waited briefly for SwiftPM's shared
in-repo `.build` lock while a test command was finishing, then completed
successfully.

## Reachability

Memory inspector path:

```text
CamiFitApp
-> ContentView toolbar brain button
-> AppInspectorState.showMemory()
-> right inspector in memory mode
-> KGMemoryPanel(store: memoryStore)
-> KGMemoryStore.load()
-> row Mark Resolved action
-> KGMemoryStore.correctHealthMemory(...)
-> validated overlay append and reload
```

Coach inspector path:

```text
CamiFitApp
-> ContentView toolbar chat button
-> AppInspectorState.toggleCoach()
-> right inspector in coach mode
-> ChatPanel
-> existing @StateObject ChatViewModel
```

The same `ContentView` owns one persistent `ChatViewModel` `@StateObject` and
one persistent `KGMemoryStore` `@StateObject`; switching modes changes only
`AppInspectorState`.

## Evidence

- Inspector mode test output:
  - `kg-memory-inspector-mode hidden_to_memory=true memory_to_coach=true state_is_value_only=true`
- Existing projection evidence still passes:
  - `kg-memory-model active=op-shoulder corrected=op-knee`
- Existing store/correction evidence still passes:
  - `kg-memory-active id=op-left-knee-pain title=Left Knee`
  - `kg-memory-corrected revision=2 status=corrected`
  - `kg-memory-load phase=empty revision=0 base=1fda44a5354e`
  - `kg-memory-validation fail_closed=stale_revision,base_hash`
- Source scan evidence:
  - `KGMemoryPanel` calls `store.correctHealthMemory(...)`.
  - Only existing Codex references remain in the coach path.
  - No `pose_worker/`, Python, `pip`, shell, or CLI memory path was added.

## Flags For Reviewer

- The visible SwiftUI app was not launched in this autonomous turn, per the
  GOAL loop/human boundary. This slice proves compile-time wiring and headless
  mode/store behavior, not human-observed UI pass/fail.
- `brain.head.profile.fill` is used for the selected state and
  `brain.head.profile` for the inactive state. If the filled variant is not
  desirable on the target SDK, swap it for a symbol variant or selected button
  tint in a visual pass.
- `Mark Resolved` uses a fixed reason string:
  `Marked resolved from Memories panel.` A future slice can add a small reason
  editor if Reviewer wants user-authored correction text in Phase 1.
- Corrupt-log quarantine and richer sections for preferences/equipment/coach
  notes remain intentionally out of scope.

## Next Suggested Slice

Close Phase 1 with a human run-verification handoff or a small reviewer-guided
polish pass:

1. Launch the macOS app and verify the toolbar chat/brain behavior visually.
2. Verify memory mode shows the expected empty state on a clean workspace.
3. Seed a local overlay memory through app-owned test data or a future debug-only
   fixture path if Reviewer approves one, then verify active/corrected rows.
4. Record manual evidence under `docs/manual-verification/`.
