# PRD: FitGraph Knowledge Graph Module

Version: 1.1
Date: 2026-06-04
Status: Draft
Owner: FitGraph

## 1. Summary

FitGraph needs a deterministic knowledge graph module that powers two product
surfaces:

- Workout Generator
- Coach AI Copilot

The LLM may parse coach language and write prose, but the graph decides workout
eligibility, safety, alternatives, and factual member-context answers.

The one-day implementation should use a small typed local property graph with a
semantic sidecar, not a full OWL/RDF runtime. The production path should preserve
the semantic-web story through RDF, SKOS, PROV-O, SHACL, ontology lockfiles, and
a low-latency serving graph.

## 2. Product Thesis

The KG module is the reasoning layer for personalized fitness recommendations.
It must prove that recommendations are graph-driven rather than LLM-improvised.

Required proof points:

- `PART_OF` anatomy closure makes `knee` include knee substructures.
- `VARIANT_OF` exercise-family closure removes all deadlift variations.
- Equipment filtering is a hard subset check.
- Active injuries and restrictions produce deterministic safety blocks.
- Alternatives are selected from the already-safe exercise pool.
- Every keep, drop, downrank, or unresolved decision emits a receipt with graph
  paths and source evidence.

## 3. Goals

- Build a small typed graph that proves deterministic runtime behavior.
- Use ontology mappings for grounding, labels, synonyms, audit, and future
  interoperability.
- Use local graph traversal for safety enforcement.
- Emit decision receipts for recommendations, filters, penalties, unresolved
  terms, and alternatives.
- Support Coach Copilot answers through graph-backed fact cards.
- Preserve a production path to RDF, SKOS, PROV-O, SHACL, and a serving graph.

## 4. Non-Goals

- Do not ingest full OPE, COPPER, or SNOMED CT OWL into the one-day runtime.
- Do not use `skos:broadMatch`, `skos:relatedMatch`, or other SKOS mappings as
  direct safety traversal edges.
- Do not use vector search for safety enforcement.
- Do not let the LLM decide eligibility.
- Do not treat all member dislikes as medical restrictions.

## 5. Users and Surfaces

### Workout Generator

The Workout Generator receives a member, a coach prompt, available equipment,
active restrictions, and goals. It returns a safe workout plan, filtered
exercises, alternatives, and decision receipts.

### Coach AI Copilot

The Coach Copilot answers structured questions about adherence, sleep, injuries,
equipment, goals, churn risk, and coach briefs. It should retrieve deterministic
fact cards before generating prose.

## 6. Architecture

### One-Day Runtime

Use a typed local property graph:

- Python dataclasses
- NetworkX
- SQLite adjacency tables
- TypeScript objects

Any of these are acceptable if the graph is typed, traversable, testable, and
receipt-producing.

### Semantic Sidecar

Required sidecar artifacts:

- `OntologyConcept` nodes
- `LocalTerm` nodes
- SKOS-style `MAPS_TO` edges
- PROV-O-shaped decision receipts
- `ontology-lock.json`
- optional RDF/Turtle export

The local taxonomy stays authoritative for runtime product behavior.

### Production Strategy

Canonical layer:

- RDF / OWL / SKOS / PROV-O
- SHACL validation
- versioned ontology lockfile
- curated terminology mappings

Serving layer:

- materialized property graph or relational graph projection
- closed-world graph snapshot
- precomputed closures
- low-latency traversal

Vector search is allowed for chat messages, coach notes, and free-text member
concerns. It is not allowed for exercise safety enforcement.

## 7. Required Nodes

### Movement and Clinical KG

- `Exercise`
- `ExerciseFamily`
- `MuscleGroup`
- `BodyRegion`
- `MovementPattern`
- `Equipment`
- `Condition`
- `SafetyRule`
- `LocalTerm`
- `OntologyConcept`
- `RecommendationRun`
- `Decision`
- `UnresolvedConcept`

### Member Context KG

- `Member`
- `Goal`
- `Preference`
- `EquipmentAvailability`
- `InjuryEpisode`
- `Restriction`
- `WorkoutSession`
- `ExercisePerformance`
- `AdherenceObservation`
- `BiomarkerObservation`
- `LabResult`
- `Message`
- `Barrier`
- `CopingStrategy`
- `ChurnSignal`
- `CoachBrief`
- `SourceSpan`

## 8. Required Edges

- `Exercise -TARGETS-> MuscleGroup`
- `Exercise -STRESSES-> BodyRegion`
- `Exercise -REQUIRES-> Equipment`
- `Exercise -HAS_PATTERN-> MovementPattern`
- `Exercise -VARIANT_OF-> ExerciseFamily`
- `BodyRegion -PART_OF-> BodyRegion`
- `Condition -AFFECTS-> BodyRegion`
- `InjuryEpisode -AFFECTS-> BodyRegion`
- `InjuryEpisode -HAS_RESTRICTION-> Restriction`
- `Restriction -APPLIES_TO_REGION-> BodyRegion`
- `Restriction -CONTRAINDICATES_PATTERN-> MovementPattern`
- `SafetyRule -USES_CONCEPT-> BodyRegion | MovementPattern | Equipment | ExerciseFamily`
- `LocalTerm -MAPS_TO-> OntologyConcept`
- `Decision -USED-> Exercise | SafetyRule | MemberFact | SourceSpan`
- `Decision -GENERATED_BY-> RecommendationRun`
- `Decision -DERIVED_FROM-> Exercise | Decision`
- `CoachBrief -DERIVED_FROM-> SourceSpan | Observation | Message`

`MAPS_TO` is for ontology grounding. It is not a substitute for local safety
edges.

## 9. Required Properties

### `STRESSES`

```json
{
  "load_level": "low | medium | high",
  "impact_level": "low | medium | high",
  "flexion_depth": "none | limited | moderate | deep",
  "loaded": true,
  "axial_load": "none | low | medium | high",
  "balance_demand": "low | medium | high",
  "laterality": "left | right | bilateral | neutral"
}
```

### `MAPS_TO`

```json
{
  "skos_predicate": "exactMatch | closeMatch | broadMatch | narrowMatch | relatedMatch",
  "confidence": 0.94,
  "method": "curated_alias | fuzzy | embedding | manual_review",
  "source": "ontology-mappings.seed.json",
  "source_version": "ontology-lock-v1",
  "review_status": "approved | candidate | rejected"
}
```

### `Decision`

```json
{
  "decision": "selected | filtered | downranked | unresolved",
  "primary_severity": "MEDICAL_HARD_BLOCK | EQUIPMENT_HARD_BLOCK | PROMPT_EXCLUSION | MEMBER_STRONG_DISLIKE | SOFT_PENALTY | BOOST",
  "reason_codes": [],
  "primary_reason_code": "",
  "score_delta": null,
  "graph_paths": [],
  "constraint_fingerprint": "",
  "graph_version": "",
  "ruleset_version": "",
  "ontology_lock_version": ""
}
```

### `UnresolvedConcept`

```json
{
  "id": "",
  "raw_text": "",
  "normalized_text": "",
  "candidate_ids": [],
  "candidate_scores": [],
  "expected_type": null,
  "resolution_status": "unresolved | needs_review | resolved",
  "safety_behavior": "block_if_safety_critical | ignore_if_non_safety | ask_clarification",
  "created_at": ""
}
```

### `SourceSpan`

```json
{
  "id": "",
  "source_file": "",
  "json_path": "",
  "text": "",
  "timestamp": null,
  "source_hash": ""
}
```

## 10. Ontology Subset

Use only concepts that affect behavior.

### OPE

Use as a scaffold for:

- exercise
- movement pattern
- equipment
- musculoskeletal region
- ailment

OPE should not be runtime truth. The local taxonomy stays authoritative.

### COPPER

Use for member-context modeling:

- profile
- preference
- activity context
- barrier
- coping strategy
- action plan
- coping plan

### SNOMED CT

Use a tiny curated subset:

- knee region
- left knee joint
- knee joint
- patella
- patellar tendon
- meniscus
- lumbar spine / lower back
- low back pain
- patellofemoral-pain-like condition candidate
- generic injury/condition hierarchy

Exact concept IDs, release IDs, licensing status, and access dates must be
verified and pinned in `ontology-lock.json` at implementation time.

### SKOS

Use SKOS for concept mappings, labels, aliases, hierarchy hints, and audit.
Do not use SKOS mappings as direct runtime safety rules.

### PROV-O

Use a minimal provenance shape:

- `RecommendationRun = Activity`
- `Decision = Entity`
- `Prompt / MemberSnapshot / Exercise / Rule = Entity`
- `SafetyEngine = Agent`
- `Decision -wasGeneratedBy-> RecommendationRun`
- `RecommendationRun -used-> Prompt / MemberSnapshot / Exercise / Rule`

The one-day implementation may represent this as JSON or graph-shaped records.

### SHACL

Use SHACL for production and CI validation of RDF graphs. Do not use SHACL as
runtime safety logic.

## 11. Resolver Requirements

The resolver returns typed constraints, not prose.

Required passes:

1. Exact, alias, or SKOS label match.
2. Fuzzy lexical match with type hint and margin.
3. Embedding fallback only when exact/fuzzy fail.

Required examples:

- `knee` -> `BodyRegion:knee` plus anatomy closure
- `left knee` -> `BodyRegion:left_knee` plus laterality
- `bad lower back` -> low-back/lumbar-spine candidate
- `kettlebell` -> `Equipment:Kettlebell`
- `no barbell` -> negated equipment constraint
- `exclude deadlifts` -> `ExerciseFamily:DeadliftFamily` exclusion
- `pecs` -> `MuscleGroup:chest`
- `squats` -> squat movement pattern and/or squat family
- `press` -> ambiguous unless slot-constrained

Failure behavior:

- Create `UnresolvedConcept`.
- Never relax safety because a term is unknown.
- Ask for clarification if interactive.
- Apply conservative fallback only when safe and explainable.

## 12. Safety Requirements

The safety engine must evaluate every candidate exercise and emit decision
receipts.

Hard blocks:

- active medical restriction
- missing or disallowed equipment
- explicit prompt exclusion
- exercise-family exclusion
- unresolved safety-critical ambiguity

Soft penalties:

- member dislike
- mild affected-region stress
- non-preferred equipment
- poor goal alignment
- high complexity under elevated churn/adherence risk

Primary severity lattice:

```text
MEDICAL_HARD_BLOCK
> EQUIPMENT_HARD_BLOCK
> PROMPT_EXCLUSION
> MEMBER_STRONG_DISLIKE
> SOFT_PENALTY
> BOOST
```

Implementation rule:

- Collect all applicable reasons.
- Choose the primary reason by the lattice.
- Store secondary reasons in the same `Decision` receipt.

## 13. Preference Policy

Prompt exclusions are hard.

Medical and equipment constraints are hard.

Member dislikes are strong soft constraints by default.

Member strong dislikes may be configured as default blocks.

A coach explicit override may override dislikes, but must never override safety
or equipment constraints.

## 14. Jordan-Specific Safety Behavior

Jordan's safety context should materialize as:

```json
{
  "active_injury": "left_knee_issue_since_2026_05_10",
  "clearance": "low_impact_loading",
  "hard_restrictions": [
    "avoid_deep_knee_flexion_under_load",
    "avoid_plyometrics",
    "avoid_high_impact_jumping"
  ],
  "available_equipment": [
    "Dumbbell",
    "Kettlebell",
    "Yoga Mat",
    "Resistance Band - Loop",
    "Flat Bench"
  ],
  "preferences": [
    "prefers_dumbbell_kettlebell",
    "trains_at_home",
    "dislikes_deadlift",
    "dislikes_burpees"
  ]
}
```

The engine should not ban every knee-related movement. It should block exercises
whose graph paths hit active restrictions.

## 15. Alternative Selection

Alternatives must come from the already-safe pool.

Scoring:

- 0.45 target muscle overlap
- 0.35 movement pattern similarity
- 0.10 equipment preference
- 0.10 priority tier
- subtract soft penalties

Receipt example:

```json
{
  "filtered": "Barbell Back Squat",
  "alternative": "Glute Bridge",
  "derived_from": "Barbell Back Squat",
  "why": [
    "shares lower-body strength goal",
    "targets glutes/hamstrings",
    "requires yoga mat only",
    "does not hit active deep-loaded-knee-flexion restriction"
  ],
  "graph_paths": [
    "Glute Bridge -TARGETS-> glutes",
    "Glute Bridge -REQUIRES-> Yoga Mat",
    "Glute Bridge -STRESSES-> hip",
    "left_knee_issue -AFFECTS-> left_knee"
  ]
}
```

## 16. Copilot Retrieval Requirements

Use direct graph queries for:

- adherence trend
- sleep this week
- last-four-weeks comparison
- workout completion
- active injuries
- available equipment
- goals
- churn risk
- coach brief
- chart data

Use vector retrieval only for:

- chat messages
- coach notes
- free-text injury notes
- open-ended member concerns

Use hybrid graph plus vector retrieval for:

- why churn risk is elevated
- what changed recently
- which messages support a concern

Use GraphRAG-style retrieval sparingly for broad summaries, not exercise safety.

## 17. Fact-Card Contract

Before LLM prose, generate fact cards:

```json
{
  "claim": "Adherence declined from 100% to 50%.",
  "confidence": "deterministic",
  "source_nodes": [
    "adherence_week_2026_05_12",
    "adherence_week_2026_06_02"
  ],
  "query": "member_retrieval.adherence_trend"
}
```

LLM instruction:

- Summarize only these fact cards.
- Do not invent member data.
- If data is absent, say the graph has no supporting fact.

## 18. API Contract

### `POST /kg/resolve`

Request:

```json
{
  "member_id": "jordan_rivera",
  "text": "No barbell, avoid deep squats, focus on glutes"
}
```

Returns resolved constraints plus unresolved concepts.

### `POST /kg/workout-candidates`

Request:

```json
{
  "member_id": "jordan_rivera",
  "prompt": "Build a 50-minute lower-body session. Exclude deadlifts. Only DB and KB."
}
```

Returns safe pool, selected exercises, filtered exercises, alternatives, and
decision receipts.

### `GET /kg/decision/:id`

Returns graph path explanation for one decision.

### `POST /kg/member-context/query`

Returns fact cards and source nodes for Copilot.

### `GET /kg/health`

Returns graph version, ruleset version, ontology lockfile version, node/edge
counts, and validation status.

## 19. Minimum Defensible Build

P0 files:

```text
graph/
  exercise_kg.seed.json
  member_kg.seed.json
  ontology_mappings.seed.json
  safety_rules.seed.json
  provenance_schema.json
  ontology-lock.json
  optional_export.ttl
```

P0 modules:

```text
kg/
  graph_store.py
  ingest.py
  resolver.py
  constraints.py
  safety.py
  alternatives.py
  provenance.py
  member_retrieval.py
  validation.py
```

P0 demo behaviors:

- `knee` includes knee substructures.
- `left knee` preserves laterality and inherits knee closure.
- `exclude deadlifts` removes all deadlift variations.
- `no barbell` filters barbell/rack/plate exercises.
- `only dumbbells and kettlebell` filters incompatible equipment and suggests
  alternatives.
- Jordan's knee restriction removes plyometrics and deep loaded knee-flexion
  exercises.
- Selected exercises explain target muscles, equipment compatibility, safety
  reasoning, and graph paths.
- Copilot answers adherence trend, sleep this week, churn risk, and coach brief
  from member-context facts.

## 20. Tests

### Resolver Tests

- `knee`
- `left knee`
- `bad lower back`
- `kettlebell`
- `no barbell`
- `only dumbbells and kettlebell`
- `exclude deadlifts`
- `pecs`
- `squats`
- `press`
- unknown term

### Safety Golden Tests

- knee injury closure
- deep knee flexion under load
- plyometrics
- no barbell
- only DB/KB
- deadlift exclusion
- limited-equipment alternatives
- dislike versus explicit exclusion
- ambiguous safety text

### Integrity Tests

- unique node IDs
- no `PART_OF` cycles
- every `Exercise` has `TARGETS`, `HAS_PATTERN`, and `STRESSES`
- every `REQUIRES` edge points to `Equipment`
- every `STRESSES` edge points to `BodyRegion`
- every active `InjuryEpisode` affects `BodyRegion`
- every hard `SafetyRule` has reason code and source
- every `MAPS_TO` edge has SKOS relation and provenance
- every selected, filtered, or downranked exercise has a `Decision` receipt

### Copilot Tests

- numeric answers exactly match graph queries
- every factual answer has source nodes
- absent data returns `not in graph`
- chat retrieval returns `Message` or `SourceSpan` nodes

## 21. Metrics

Primary safety metric:

- `unsafe_allowed_rate = 0` on golden cases

Secondary metrics:

- `safe_filtered_rate`
- `alternative_availability_rate`
- `provenance_completeness`
- `resolver_accuracy`
- `unresolved_safety_term_count`
- `p95_latency`

## 22. Open Questions

- What is the exact repo stack and preferred implementation language?
- How much evaluator weight goes to RDF/SKOS/PROV artifacts versus runtime
  graph behavior?
- Which exact SNOMED CT concepts and release IDs should be pinned?
- Do member strong dislikes default to hard blocks or strong penalties?
- Should ontology review be represented as code review, data review, or both?

## 23. Final Direction

Maintain the strategy:

- Build a small typed graph that proves deterministic behavior.
- Use ontology mappings for grounding.
- Use decision receipts for explainability.
- Use direct graph queries for member facts.
- Let the LLM parse and verbalize, but never decide eligibility.
