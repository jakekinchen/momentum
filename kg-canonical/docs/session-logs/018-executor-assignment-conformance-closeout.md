# Executor Log 018 - Assignment Conformance Closeout

Date: 2026-06-06

Active brief: `docs/briefs/017-assignment-conformance-closeout.md`

## Summary

Resumed the KG subtree under fresh human direction from the app-level
assignment closeout brief. Implemented the app/KGKit assignment path so the
Swift runtime can load the full generated 50-exercise assessment graph, route
coach workout requests through deterministic KGKit generation, expose
decision/provenance evidence in chat, and answer assignment Copilot quick
prompts from graph-backed member facts.

## Subagents

- Pasteur audited Python gate/documentation command drift and confirmed the
  active surfaces needing `uv run python -m pytest`.
- Curie audited the 50-exercise graph promotion path and caught the Swift
  generic-knee/left-knee traversal gap before closeout.
- Poincare audited the app coach flow, routine mapping, and provenance UI path.
- Singer audited resolver, motion readiness, and ontology/provenance gaps.

## Changed Areas

- Added assignment KGKit resources:
  `Sources/KGKit/Resources/Artifact/kg_artifact.assessment.v0.json` and
  `Sources/KGKit/Resources/Artifact/assessment_member_kg.generated.json`.
- Added app-side deterministic planner and Copilot providers:
  `AssignmentWorkoutPlanner`, `KGWorkoutPlanCard`, `AssignmentCopilotProvider`,
  and `AssignmentCopilotFactCardView`.
- Routed workout and assignment quick prompts locally before Codex freeform
  prose, while keeping freeform exercise authoring disabled.
- Extended resolver metadata with `confidence` and `resolution_method`, plus
  high-confidence local typo aliases.
- Added motion-readiness JSON report support and generated
  `scripts/motion_reference/kg_motion_readiness.assessment.v0.json`.
- Updated active README/gate commands to use `uv run python -m pytest`.
- Fixed the monorepo artifact-build gate to compare generated paths before and
  after generation, so it catches real generator drift without requiring a clean
  diff against `HEAD` during an uncommitted implementation slice.
- Documented ontology/provenance scope without claiming verified ontology IDs.

## Validation Evidence

```bash
uv run python -m pytest
# 153 passed in 11.55s
```

```bash
uv run python -m kg.validation
# validation_status: pass
# schema_validation_status: pass
# ontology_status: todo_unverified
# verified: false
```

```bash
uv run python -m kg.assessment_import
# status: pass
# exercise_count: 50
# generated_exercise_node_count: 212
# generated_exercise_edge_count: 512
# member_sections_missing: []
```

```bash
swift test --disable-sandbox
# 273 tests passed
```

```bash
bash scripts/validate_resume_brief.sh docs/briefs/017-assignment-conformance-closeout.md
bash scripts/audit_autonomous_workflow.sh
node scripts/audit_codex_pair_state.mjs
# clean / pass
```

```bash
scripts/motion_reference/audit_motion_coverage.py --strict
# presets=4 profiles=4 pending_reference_captures=0 failures=0

scripts/motion_reference/audit_kg_motion_readiness.py --summary-only
# generated kg_exercises=50 guide_ready=0 archetype_demo_only=25
# recommend_only=25 mapped_incomplete=0
# generated_missing=0
```

```bash
git diff --check
# pass
```

```bash
scripts/run_monorepo_gates.sh
# pass: kg Python tests, kg.validation, kg.assessment_import, artifact
# idempotence, Swift conformance parity, full swift test, motion coverage,
# KG motion readiness, and contracts listing
```

## Guardrails

- Deterministic graph behavior remains the workout safety authority.
- Codex instructions no longer ask the LLM to emit freehand `future-routine`
  JSON for workout requests.
- `MAPS_TO` remains ontology audit metadata.
- No vector search or embedding path enforces safety.
- No verified SNOMED/OPE/COPPER/license/release/access-date claim was
  introduced; `ontology-lock.json` remains unverified.
- KG exercises can be recommendation inputs across all 50 golden exercises, but
  visible guide/measurement support remains limited to motion-ready app presets
  and explicit archetype mappings.

## Remaining Work

- A richer production Copilot UI can still be designed beyond the current chat
  fact-card surface.
- Exact KG-exercise-to-app-preset curation should remain a reviewed mapping
  lane; current archetype mapping is intentionally labeled.
- Verified ontology lockfile/RDF/SKOS/PROV-O/SHACL remains future production
  work.
