# Brief 045 - KG Memory Inspector UI Wiring

## Feature

Wire the Phase 1 KG memory store into the CamiFit right inspector. The user should be able to open a brain-icon memory mode, inspect active/corrected health and safety memories, and trigger the existing app-owned correction path without replacing the coach chat model.

## Why This Slice Exists Now

Brief 044 established the app-owned `KGMemoryStore`, projection models, and correction path. The remaining Phase 1 MVP work is the product-visible inspector mode and panel. This slice should connect the new store to the existing SwiftUI shell without adding Codex proposal flows, recommendation receipt deep-links, or broader KG product loops.

## Acceptance Criteria

- `ContentView` has a right-inspector mode enum with `coach` and `memory`.
- The existing chat toolbar behavior is preserved:
  - if the inspector is hidden, clicking chat opens it in `coach` mode;
  - if the inspector is hidden, clicking the brain button opens it in `memory` mode;
  - switching modes does not replace the existing `ChatViewModel`.
- Add an icon-only SF Symbol brain button, preferably `brain.head.profile`, with tooltip/help text `Memories`.
- Add `Sources/CamiFitApp/KGMemoryPanel.swift`.
- `KGMemoryPanel` renders:
  - loading, empty, and error states;
  - header with `Memories`, overlay revision, and base artifact short hash;
  - active health/safety memory rows;
  - corrected health/safety memory rows;
  - operation id, source text, actor, date, status, compact reason, and evidence when present.
- Active health/safety rows expose exactly one correction action that calls `KGMemoryStore.correctHealthMemory(operationID:reason:)`.
- Correction reloads the store state through the existing store path.
- Do not add a user-visible CLI or shell command path for KG memories.
- Do not add Codex-proposed memory approval flows.
- Do not mutate the immutable base graph artifact.
- Do not make live-app behavior claims beyond what headless tests prove.

## Expected Files

- `Sources/CamiFitApp/ContentView.swift`
- `Sources/CamiFitApp/KGMemoryPanel.swift`
- `Tests/CamiFitAppTests/KGMemoryPanelModelTests.swift` or another focused app test file
- `docs/session-logs/045-executor-kg-memory-inspector-ui-wiring.md`

Only touch `KGMemoryStore` or `KGMemoryModels` if the panel needs a small app-facing helper that can be tested headlessly.

## Validation Commands

Run:

```bash
swift test --disable-sandbox --filter KGMemoryStoreTests
swift test --disable-sandbox --filter KGMemoryPanelModelTests
swift test --disable-sandbox --filter CamiFitAppTests
swift build --disable-sandbox
git diff --check
scripts/audit_autonomous_workflow.sh
```

If SwiftUI structure allows a deterministic model test for mode switching or chat-model preservation, add it. If not, record why the behavior is wireable but requires human run-verification before claiming visible app behavior.

## Evidence Required

The executor log must include:

- files changed;
- validation command outputs;
- evidence that the inspector can choose `coach` vs `memory` mode;
- evidence that memory mode uses `KGMemoryStore`;
- evidence that the correction action routes through `correctHealthMemory`;
- confirmation that no CLI, Codex proposal bridge, Python dependency, model download, or `pose_worker/` change was added.

## Reachability

The UI path should be:

```text
CamiFitApp
-> ContentView toolbar brain button
-> right inspector in memory mode
-> KGMemoryPanel
-> KGMemoryStore.load()
-> KGMemoryStore.correctHealthMemory(...)
-> validated overlay append and reload
```

The coach path should continue to use the same persistent `ChatViewModel`:

```text
CamiFitApp
-> ContentView toolbar chat button
-> right inspector in coach mode
-> ChatPanel
-> existing ChatViewModel instance
```

## Out Of Scope

- Codex-proposed memory approval flows.
- Recommendation receipt cards or deep-links.
- Base-vs-member plan comparison UI.
- Fact-card grounding in coach turns.
- Completed-session KG write-back.
- Export/reset/local data controls.
- Corrupt-log quarantine.
- Compaction/redaction.
- Live camera verification or human-observed SwiftUI pass/fail claims.
