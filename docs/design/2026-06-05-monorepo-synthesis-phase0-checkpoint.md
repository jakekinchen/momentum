# Monorepo Synthesis Phase 0/A Checkpoint

Date: 2026-06-05

Branch: `feat/monorepo-synthesis`

Worktree: `/Users/kelly/Developer/camifit-monorepo-synthesis`

## Purpose

Record the pre-import checkpoint for the CamiFit + FitGraph monorepo synthesis.
This checkpoint covers the reversible setup steps before importing FitGraph
history under `kg-canonical/` and deduplicating the candidate-assessment golden
data.

## Source State

- CamiFit synthesis base tag: `pre-monorepo-freeze`
- Tagged commit: `dcd95fd`
- Integration branch base: `origin/main` at `a90ed8d`
- Merged source branch: local `feat/chat-regimen` at `dcd95fd`
- Merge commit: `7eb0578`
- FitGraph oracle source: `/Users/kelly/Developer/fitgraph`
- FitGraph commit: `2597993`
- FitGraph backup bundle:
  `/Users/kelly/Developer/fitgraph-backup-2026-06-05.bundle`

## Parity Baselines

These hashes were recorded before the branch reconciliation and rechecked after
the merge.

```text
1fda44a5354ed1cf199b63a5df0ef691052e8d23b95254e5ad545e41b2cfa562  Sources/KGKit/Resources/Artifact/kg_artifact.v0.json
fcdfbef8bcc239844214dbced7c474a8bb120b64bb9991a2d41bf5ee885cc117  Tests/KGKitTests/Fixtures/conformance/safety_vectors.json
```

## Verification

```bash
swift --version
# Apple Swift version 6.3.2; target arm64-apple-macosx26.0
```

```bash
swift build
# Passed on the original `feat/chat-regimen` tree.
```

```bash
git bundle verify /Users/kelly/Developer/fitgraph-backup-2026-06-05.bundle
# Bundle is complete and contains FitGraph `main` at 2597993.
```

```bash
git merge feat/chat-regimen
# Completed without conflicts on `feat/monorepo-synthesis`.
```

```bash
grep -Rsn "exerciseAuthoringEnabled = false" Sources/CamiFitApp Tests/CamiFitAppTests
test -f Tests/CamiFitAppTests/CoachAuthoringGateTests.swift
test -d Sources/KGKit
# Authoring gate and KGKit both survived the auto-merge.
```

```bash
swift build
# Passed on the merged integration branch.
```

```bash
swift test
# 151 tests passed on the merged integration branch.
```

```bash
swift test --filter ConformanceTests
# 1 test passed; Swift KGKit still reproduces the oracle receipts.
```

## Known Non-Blocking Warnings

- `Sources/CamiFitApp/LivePoseWorkerClient.swift` reports an unused
  `withUnsafeMutablePointer(to:_:)` result warning.
- `Tests/CamiFitAppTests/ChatRegimenParseTests.swift` uses the deprecated
  `String(contentsOf:)` initializer warning under the current SDK.

## Next Slice

Import FitGraph history with:

```bash
git subtree add --prefix=kg-canonical /Users/kelly/Developer/fitgraph main
```

Then run the Python oracle checks from `kg-canonical/`, deduplicate
candidate-assessment into `data/golden/candidate-assessment/`, patch
`kg-canonical/kg/assessment_import.py`, regenerate conformance artifacts with
`FITGRAPH=$(pwd)/kg-canonical`, and assert the parity baselines above remain
unchanged.
