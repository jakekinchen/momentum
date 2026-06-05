# Monorepo Synthesis Phase C/D Checkpoint

Date: 2026-06-05

Branch: `feat/monorepo-synthesis`

Worktree: `/Users/kelly/Developer/camifit-monorepo-synthesis`

## Purpose

Record the history-preserving FitGraph import and candidate-assessment golden
deduplication checkpoint for the CamiFit monorepo synthesis.

## Imported Oracle

FitGraph was imported with the builtin subtree path:

```bash
git subtree add --prefix=kg-canonical /Users/kelly/Developer/fitgraph main
```

Imported FitGraph source commit:

```text
259799330f3813cc6b93e083c67b561fc6d7190d
```

Subtree import commit:

```text
a6b9b0a Add 'kg-canonical/' from commit '259799330f3813cc6b93e083c67b561fc6d7190d'
```

The durable backup bundle remains:

```text
/Users/kelly/Developer/fitgraph-backup-2026-06-05.bundle
```

## Golden Data Deduplication

The byte-identical CamiFit and FitGraph candidate-assessment snapshots were
collapsed into one canonical copy:

```text
data/golden/candidate-assessment/
```

The redundant paths were removed:

```text
docs/requirements/candidate-assessment/
kg-canonical/docs/external/candidate-assessment/
```

The retained provenance manifest is:

```text
data/golden/candidate-assessment/PROVENANCE.md
```

It merges the CamiFit "floor, then surpass" framing with the FitGraph source
snapshot hashes and license-absence note.

## Importer Repair

`kg-canonical/kg/assessment_import.py` now resolves the golden fixture from the
monorepo root:

```text
data/golden/candidate-assessment/data/
```

Generated SourceSpan and graph `source.path` fields now stamp:

```text
data/golden/candidate-assessment/data/exercises.json
data/golden/candidate-assessment/data/member-context.json
```

## Validation Evidence

```bash
UV_CACHE_DIR=/private/tmp/camifit-uv-cache uv run pytest
# 152 passed in 11.58s
```

```bash
UV_CACHE_DIR=/private/tmp/camifit-uv-cache uv run python -m kg.validation
# validation_status: pass
# schema_validation_status: pass
# verified: false
```

```bash
UV_CACHE_DIR=/private/tmp/camifit-uv-cache uv run python -m kg.assessment_import
# status: pass
# actual_counts: 50 exercises, 19 muscle groups, 9 loaded body regions,
#                36 movement patterns, 32 equipment terms
# generated: 212 exercise nodes / 512 exercise edges
# generated: 77 member nodes / 97 member edges
```

```bash
FITGRAPH=$(pwd)/kg-canonical python3 scripts/gen_kg_conformance_vectors.py
# wrote Sources/KGKit/Resources/Artifact/kg_artifact.v0.json:
#   28 nodes / 39 edges / 3 rules
# wrote Tests/KGKitTests/Fixtures/conformance/safety_vectors.json:
#   28 vectors
```

The Phase 0/A parity baselines still match after regeneration:

```text
1fda44a5354ed1cf199b63a5df0ef691052e8d23b95254e5ad545e41b2cfa562  Sources/KGKit/Resources/Artifact/kg_artifact.v0.json
fcdfbef8bcc239844214dbced7c474a8bb120b64bb9991a2d41bf5ee885cc117  Tests/KGKitTests/Fixtures/conformance/safety_vectors.json
```

```bash
swift test --filter ConformanceTests
# 1 test passed
```

```bash
swift test
# 151 tests passed
```

## Guardrails

- FitGraph remains the Python build-time oracle under `kg-canonical/`.
- KGKit remains the Swift runtime surface under `Sources/KGKit/`.
- Candidate-assessment is now a single golden source snapshot under
  `data/golden/`.
- The Swift artifact and conformance vectors were regenerated from
  `FITGRAPH=$(pwd)/kg-canonical` and remained byte-identical.
- No verified ontology, SNOMED, OPE, COPPER, license, or release-date claim was
  introduced.

## Next Slice

Promote `scripts/run_monorepo_gates.sh` into hosted CI once the target macOS
runner image and Swift toolchain are pinned. The local gate already covers:

- `kg-python`: `cd kg-canonical && uv run pytest`
- `kg-validation`: `cd kg-canonical && uv run python -m kg.validation`
- `assessment-import`: regenerate generated assessment graph snapshots
- `artifact-build`: regenerate KGKit artifact/vectors and fail on generated
  artifact drift
- `conformance-parity`: `swift test --filter ConformanceTests`
- `swift-test`: `swift test`
- `contracts-compat`: pending until `contracts/` is introduced
