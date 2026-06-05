# 044 Executor - KG Memory Store Foundation

## Slice

Implemented the smallest Phase 1 memory-inspector foundation from
`docs/briefs/044-kg-memory-inspector-panel.md`: make `CamiFitApp` depend on
`KGKit`, add app-facing memory projection models, and add an app-owned
`KGMemoryStore` that prepares/loads the local KG workspace and appends validated
`RetractMedicalConstraint` corrections.

No UI panel, brain button, Codex proposal bridge, receipt deep-linking, or CLI
surface was added in this slice.

## Files Changed

- `Package.swift`
  - Added `KGKit` to `CamiFitApp`.
  - Added `KGKit` to `CamiFitAppTests` for fixture workspace construction.
- `Sources/CamiFitApp/KGMemoryModels.swift`
  - Added SwiftUI-facing `KGMemoryItem`, category/status enums, and
    `KGMemoryViewState`.
- `Sources/CamiFitApp/KGMemoryStore.swift`
  - Added `ObservableObject` store for `KGWorkspace.prepare(...)`,
    `GraphOperationLog`, `OverlayValidator`, and active/corrected medical
    memory projection.
  - Added `correctHealthMemory(operationID:reason:)`, which appends
    `RetractMedicalConstraint` with current base hash and overlay revision, then
    reloads.
- `Tests/CamiFitAppTests/KGMemoryStoreTests.swift`
  - Covered initial workspace load, active medical-memory projection,
    retraction/corrected projection, base artifact immutability, merged-view
    safety rerun, and fail-closed validator behavior for stale revision/base
    mismatch.
- `Tests/CamiFitAppTests/KGMemoryPanelModelTests.swift`
  - Covered app-facing active/corrected row projection ordering and metadata.

## Validation

Initial focused test attempts failed because generated SwiftPM module-cache
files in `.build` were compiled under
`/Users/kelly/Developer/camifit-monorepo-synthesis` while this checkout is
`/Users/kelly/Developer/camifit-app`:

```text
precompiled file ... SwiftShims ... was compiled with module cache path
'/Users/kelly/Developer/camifit-monorepo-synthesis/.build/...'
but the path is currently
'/Users/kelly/Developer/camifit-app/.build/...'
```

Direct removal of the generated module-cache directory was blocked by command
policy, so I ran SwiftPM's generated-product cleanup:

```bash
swift package clean
```

After that, validation passed:

```bash
swift test --disable-sandbox --filter KGMemoryStoreTests
# passed: 4 tests, 0 failures
```

```bash
swift test --disable-sandbox --filter KGMemoryPanelModelTests
# passed: 1 test, 0 failures
```

```bash
swift test --disable-sandbox --filter KGKitTests
# passed: 56 tests, 0 failures
```

```bash
swift test --disable-sandbox --filter CamiFitAppTests
# passed: 59 tests, 0 failures
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

## Reachability

The real product target now has a direct `CamiFitApp -> KGKit` package
dependency. `KGMemoryStore` defaults to `KGWorkspace.applicationSupportDirectory`
and `ArtifactLoader.bundledData()`, so the app-owned path is:

```text
CamiFitApp target
-> KGMemoryStore.load()
-> KGWorkspace.prepare(Application Support/CamiFit/KnowledgeGraph, bundled artifact)
-> GraphOperationLog(current.jsonl)
-> MemberOverlayState/app-facing KGMemoryItem projection
-> KGMemoryStore.correctHealthMemory(...)
-> GraphOperationLog.append(RetractMedicalConstraint, OverlayValidator)
-> reload merged overlay state
```

The tests exercise that path with a real prepared workspace and the bundled KG
artifact. They also verify the base artifact bytes are unchanged after
correction and that `MergedGraphView` no longer exposes the corrected medical
constraint.

## Evidence

- Empty load evidence:
  - `kg-memory-load phase=empty revision=0 base=1fda44a5354e`
- Active memory evidence:
  - `kg-memory-active id=op-left-knee-pain title=Left Knee`
- Corrected memory evidence:
  - `kg-memory-corrected revision=2 status=corrected`
- Fail-closed evidence:
  - `kg-memory-validation fail_closed=stale_revision,base_hash`
- Projection evidence:
  - `kg-memory-model active=op-shoulder corrected=op-knee`

## Flags For Reviewer

- This is a foundation slice only. The right inspector mode enum, brain toolbar
  button, and visible `KGMemoryPanel` remain unimplemented.
- `KGMemoryStore` currently projects only `AddMedicalConstraint` plus
  `RetractMedicalConstraint`, matching the Phase 1 health/safety correction
  requirement. Preferences/equipment/coach notes should be added when the UI
  surface needs those sections.
- The operation id generated for app-owned retractions is deterministic in
  shape but includes `UUID()`. If the Reviewer wants stable ids for tests or
  receipts, the next slice should inject an id generator.
- `scripts/audit_autonomous_workflow.sh` reports README files as "latest"
  artifacts because of filename sorting, but GOAL.md and this log both point to
  active brief 044.

## Next Suggested Slice

Wire `ContentView` to the store without expanding feature scope:

1. Add an inspector mode enum with `coach` and `memory`.
2. Preserve the existing `ChatViewModel` as a single `@StateObject`.
3. Add a brain icon toolbar button that opens the inspector in memory mode.
4. Add a minimal `KGMemoryPanel` that renders loading/empty/error/header states
   plus active/corrected rows from `KGMemoryStore`.
5. Add focused tests for inspector mode switching and chat model preservation if
   the current SwiftUI structure allows headless coverage.
