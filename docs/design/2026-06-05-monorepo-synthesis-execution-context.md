I have a fully verified critic punch-list and the source analyses. The draft is well-structured; my job is to apply every punch-list correction faithfully. Let me produce the final document directly as my return value.

# Monorepo Synthesis — Standalone Execution Context

**Document version:** 2026-06-05 · **Status:** authoritative hand-off context for a fresh agent · **Scope:** combine three local repos (`candidate-assessment`, `fitgraph`, `camifit`) into one monorepo per the canonical synthesis architecture.

> **Verification note (this doc is fact-checked against disk on 2026-06-05).** Where the upstream source analyses disagree with disk, **disk wins** and the correction is called out inline. The corrections that matter most:
> 1. **The feat↔origin/main merge is conflict-free.** `git merge-tree --write-tree feat/chat-regimen origin/main` produces a clean tree (object `f4fe2de…`) with **zero conflict markers**, in **either** merge direction. Earlier framing of `Package.swift` / `CodexAppServerClient.swift` as "conflict points requiring manual resolution" is **false** — git 3-way auto-merges both. The ONLY required manual action in branch reconciliation is **verification**, not conflict resolution. (See §6.2.)
> 2. **Only the authoring-gate flag + its guard test are origin/main-only.** The regimen parse/store/card pipeline (`Sources/CamiFitApp/Regimen/*` and `CodexAppServerClient.swift`) is **already shared** from merge-base `9b8b8cc` and is present in the `feat/chat-regimen` working tree right now. The genuinely main-only additions are exactly: `exerciseAuthoringEnabled = false` + its guard `return persona` + `CoachAuthoringGateTests.swift`, all introduced by commit `b6577f8`, touching exactly two files.
> 3. **The frozen Swift artifact is 28 nodes / 39 edges / 3 rules** (decoded from `Sources/KGKit/Resources/Artifact/kg_artifact.v0.json`), NOT "25/28". The TARGET/plan source docs say "25/28" and are **wrong** — the plan doc `docs/superpowers/plans/2026-06-04-swift-kgkit-safety-core.md` itself needs that figure corrected, or regenerating the artifact and diffing against the plan's stated counts will look like a regression.
> 4. **KGKit = 10 Swift source files** (`ls Sources/KGKit/*.swift`) + `README.md` + `Resources/Artifact/kg_artifact.v0.json` + `.gitkeep`. The "12"/"14 source files" figures in some analyses miscount README/resources/`.gitkeep` as sources. **KGKitTests = 12 Swift test files** + 1 conformance fixture (`Fixtures/conformance/safety_vectors.json`, which is data, not a suite).
> 5. **`fitgraph` HEAD is `2597993`, working tree CLEAN, no git remote.** Older analyses report `87395dc` + a dirty tree ("10 changed files"); that in-flight test work is already committed in `2597993` and the tree is now clean (`git status --porcelain` empty). The "commit in-flight work first" step is therefore a no-op (keep it as a `git status` assertion only).
> 6. **`feat/chat-regimen` is fully pushed** to `origin/feat/chat-regimen` (`20 0` — 20 ahead of origin/main, 0 behind its own remote). The REQS+GIT source's "20 unpushed commits" is stale; do not re-derive that conclusion.
> 7. The doc `docs/design/2026-06-04-three-repo-kg-camifit-synthesis-plan.md` named in some prompts **does not exist on disk**; the canonical synthesis doc is `docs/design/2026-06-04-camifit-fitgraph-synthesis.md`.

---

## 1. Purpose & audience

This document lets a fresh agent (no prior context) execute the **full monorepo synthesis**: fold three currently-separate local repositories into one git root where a Python knowledge-graph oracle compiles a signed artifact that a Swift on-device runtime serves, and a SwiftUI app decides→authors→runs workouts with deterministic safety.

**The system being built is a decide → author → run loop:**
- **Decide:** a closed-world knowledge graph (deterministic traversal, never the LLM) decides workout eligibility, injury safety, equipment filtering, and alternatives, emitting an auditable `DecisionReceipt`.
- **Author:** safe candidates compile into runnable `ExerciseProgram`s via a constrained grammar (never free-LLM authoring).
- **Run:** the on-device pose/rep/form engine grades execution offline and writes typed observations back into an append-only member overlay.

**"Done" for the synthesis means all of the following hold:**
1. One git root contains all three repos' content, with `candidate-assessment` deduplicated to a single vendored golden copy.
2. `fitgraph`'s Python history is preserved (it has **no git remote** and exists only on this machine — losing it is unrecoverable).
3. The camifit divergence is reconciled: the **KGKit Swift module + synthesis docs** (on `feat/chat-regimen`) AND the **`exerciseAuthoringEnabled=false` gate + `CoachAuthoringGateTests`** (on `origin/main`) coexist in one tree. Neither branch currently has both. (The regimen parse/store/card pipeline is already on both — it is shared from `9b8b8cc`.)
4. `Package.swift` builds `CamiFitEngine` + `KGKit` + the app together; `swift build` and `swift test` pass.
5. The cross-language **conformance-parity gate is green**: the Swift KGKit runtime reproduces the Python oracle's receipts byte-for-byte, including the `sha256[:16]` `constraint_fingerprint`.
6. CI gate set is wired (`kg-python`, `kg-validation`, `artifact-build`, `swift-test`, `conformance-parity`, `contracts-compat`).

**Audience:** an autonomous coding agent doing the physical merge + CI wiring. This is NOT the architecture spec (that is `docs/design/2026-06-04-camifit-fitgraph-synthesis.md`, §1–§11) — this is the executable hand-off.

---

## 2. The three repos today

### 2.1 `candidate-assessment` — the immutable golden spec
- **Path:** `/Users/kelly/Developer/candidate-assessment`
- **Language:** Markdown + JSON (no code)
- **Role:** the read-only requirements floor — a staff-level take-home spec. "Contain it, then surpass it."
- **State:** branch `main`, HEAD **`4b8c67246a659c26bd222079c5c7829d295acad9`**, remote `origin → github.com/future-research/candidate-assessment.git`, **clean (0/0, pristine)**, in sync with origin. The ONLY one of the three repos that is both pushed and remotely backed up.
- **Key artifacts:** `ASSESSMENT.md`, `README.md`, `data/exercises.json` (a JSON **array of 50 exercises**, taxonomy cardinalities **19 muscle groups / 9 joints / 36 movement patterns / 32 equipment**), `data/member-context.json` (one synthetic member **Jordan Rivera** `mbr_01HX9JORDAN`: profile/goals/preferences/injuries[left knee, patellofemoral]/chat/biomarkers/labs/workout_history/adherence[declining]/coach_brief[churn elevated]).
- **What it requires (the conformance floor):** coach-facing dashboard with two surfaces — (A) Workout Generator (free-text prompt + time window → warmup/main/cooldown with sets/reps/rest, graph-driven exclusion + injury-via-anatomy-hierarchy + equipment-swap, provenance trace) and (B) Coach Copilot (retrieval over member KG, morning brief, quick-prompts, charts, grounded answers). Plus KG modeling (KG1 movement/clinical, KG2 member), ontology grounding (OPE/COPPER/SNOMED/PROV-O/SKOS), a 3-pass resolver (exact→fuzzy→embedding with confidence + graceful degradation), **safety-from-traversal** (the central invariant), PROV-O provenance, mandated tests for resolver + safety filter, and a README defensible in review. No automated harness ships — review is human.

### 2.2 `fitgraph` — the Python KG oracle (canonical truth, build-time only)
- **Path:** `/Users/kelly/Developer/fitgraph`
- **Language:** Python 3.10+, **zero runtime dependencies**, invoked via `uv` (`pyproject.toml` 451 bytes + `uv.lock` ~21 KB both at repo root — both must land at `kg-canonical/` root for `uv sync` to work).
- **Role:** deterministic, dependency-free knowledge-graph layer — the canonical oracle. **Never ships at runtime.** Its one invariant: an LLM may parse coach language in or verbalize bounded facts out, but **local typed graph traversal alone decides** eligibility/safety/equipment/alternatives.
- **State:** branch `main`, HEAD **`2597993`** (the in-flight test work older analyses saw as uncommitted is now committed here), **working tree CLEAN** (`git status --porcelain` empty), **NO git remote configured — exists only on this machine.** Treat preservation of history as mandatory.
- **`kg/` modules (13 + `__init__`):** `graph_store.py` (closed-world `LocalGraph`, PART_OF BFS/DFS traversals), `constraints.py` (`ResolvedConstraint`), `resolver.py` (text→typed constraints, exact/alias + hardcoded canonical cases; **no fuzzy/embedding — by design**), `safety.py` (6-level severity lattice, 3 reason generators, `DecisionReceipt`, `evaluate_candidates`), `alternatives.py` (`select_alternatives`, weighted score `0.45·target+0.35·pattern+0.10·equip+0.10·priority`, `round(…,6)`, `(-score,id)` tie-break), `provenance.py` (`stable_fingerprint` = `sha256(json.dumps(sort_keys,separators=(",",":")))[:16]`), `member_retrieval.py` (7 fact cards + 5 chart series), `validation.py` (health/integrity CLI; version constants `GRAPH_VERSION="fitgraph-kg-m5-validation-v0"`, `RULESET_VERSION="ruleset-m2-safety-v0"`), `ingest.py`, `assessment_import.py` (the build-time compiler; reads frozen `docs/external/candidate-assessment/data/*.json` pinned at `SOURCE_SNAPSHOT_COMMIT=4b8c672…`, builds full 50-exercise graph, hits exact-count gate — see §6.5 for its path coupling), `workout_generator.py` (end-to-end CLI), `copilot.py` (CLI).
- **`graph/` artifacts:** hand-curated runtime seeds (`exercise_kg.seed.json` 28 nodes/39 edges, `member_kg.seed.json` 32 nodes/43 edges, `safety_rules.seed.json` 3 MEDICAL_HARD_BLOCK rules, `ontology_mappings.seed.json` audit-only, `ontology-lock.json` `verified:false`, `provenance_schema.json` placeholder) + `graph/generated/` full-fixture baseline (212 nodes/512 edges exercise, 77 nodes/97 member, conformance summary `status:pass`).
- **Packaging:** `pyproject.toml`, package `fitgraph-kg` v0.1.0, no console_scripts — invoked via `python -m kg.*`. Tests = 14 `tests/test_*.py` files (the oracle).

### 2.3 `camifit` — the Swift app + the partial KGKit port
- **Path:** `/Users/kelly/Developer/camifit`
- **Language:** Swift (SwiftPM, tools 5.9, platform macOS 26.0)
- **Role:** the shipping product — SwiftUI macOS shell + pose/rep/form engine + on-device KG serving runtime.
- **State:** current branch **`feat/chat-regimen`**, HEAD **`867192c`**; default `main`; remote `origin → github.com/jakekinchen/camifit.git`. **`feat/chat-regimen` is diverged (not linear) from `origin/main` (tip `a90ed8d`): ahead 20 / behind 3, merge-base `9b8b8cc`.** Local `feat/chat-regimen` is **fully in sync with `origin/feat/chat-regimen` (`20 0`) — all 20 commits ARE pushed there**, just not on origin/main.
- **Targets (feat/chat-regimen `Package.swift`):** products `CamiFitEngine`, `CamiFitApp`, **`KGKit`** (feat-only); targets `CamiFitEngine`, `KGKit` (`exclude:["README.md"]`, resource `.copy("Resources/Artifact")`), `KGKitTests` (dep `[KGKit]`, resource `.copy("Fixtures")`), `CamiFitApp`, `CamiFitEngineTests`, `CamiFitAppTests`. **`origin/main`'s `Package.swift` is identical EXCEPT it has no KGKit product/targets** (verified: `git ls-tree origin/main -- Sources/KGKit` is empty).
- **`Sources/CamiFitEngine/` (21 files):** pose I/O, program model, rep/set/form state machines, an Expression DSL (Lexer/Parser/AST/Evaluator), trace recorder. KG-agnostic.
- **`Sources/CamiFitApp/` (23 files):** SwiftUI shell, live camera/pose overlay, `AppExerciseSessionViewModel`, `CodexAppServerClient` (the coach), and `Regimen/` plumbing (parser/store/cards/routines). **All present on BOTH branches (shared from `9b8b8cc`)** — only the gate flag + guard test inside `CodexAppServerClient.swift`/Tests differ (see §4).
- **`Sources/KGKit/` — 10 Swift source files + README + frozen artifact + `.gitkeep`:** the safety-core Swift port. Swift files: `Version.swift`, `GraphModel.swift`, `GraphArtifact.swift`, `ArtifactLoader.swift`, `LocalGraph.swift`, `SafetyRule.swift`, `ResolvedConstraint.swift`, `DecisionReceipt.swift`, `CanonicalJSON.swift`, `SafetyEngine.swift` (= **10**). Non-Swift tracked files: `README.md`, `Resources/Artifact/.gitkeep`, `Resources/Artifact/kg_artifact.v0.json`. The artifact header: `graph_version=fitgraph-kg-m5-validation-v0`, `ruleset_version=ruleset-m2-safety-v0`, `ontology_lock_version=ontology-lock-m0-unverified`, **28 nodes / 39 edges / 3 safety_rules** (frozen copy of the hand-curated seed).
- **`Tests/KGKitTests/` — 12 test suites + 1 conformance fixture:** suites `ConformanceTests`, `CanonicalFingerprintTests`, `MedicalReasonsTests`, `EquipmentAndExclusionReasonsTests`, `EvaluateCandidatesTests`, `SeverityLatticeTests`, `PartOfTraversalTests`, `LocalGraphTests`, `GraphArtifactDecodeTests`, `GraphModelTests`, `NodeIDTests`, `ModuleSmokeTests` (= **12 `.swift` files**); plus the data fixture `Fixtures/conformance/safety_vectors.json` (NOT a suite) and `Fixtures/.gitkeep`.
- **Cross-repo bridge files (already in camifit):** oracle/freezer `scripts/gen_kg_conformance_vectors.py` (imports live Python `kg/` via `FITGRAPH=` env, freezes seed→Swift artifact, emits golden vectors), CI gate `Tests/KGKitTests/ConformanceTests.swift`, canonical plan `docs/design/2026-06-04-camifit-fitgraph-synthesis.md`, KGKit plan `docs/superpowers/plans/2026-06-04-swift-kgkit-safety-core.md`.

---

## 3. Target architecture

### 3.1 decide → author → run

```
 L1  Chat / Copilot (LLM)        parses coach text IN, verbalizes facts OUT — NEVER decides
        │  free text + time window
        ▼
 L2  Swift KG runtime (KGKit)    DECIDE: closed-world traversal → DecisionReceipt (safety/eligibility)
        │  WorkoutCandidateResult (selected/filtered/alternatives + receipts)
        ▼
        │  AUTHOR: ProgramCompiler turns safe candidates → ExerciseProgram (constrained grammar)
        ▼
 L3  Exercise engine (CamiFitEngine)   RUN: pose-grade reps/form offline → ExercisePerformance
        │  observations
        ▼
     Member overlay (App Support, append-only)   write-back, never edits canonical safety
        ▲
        │  frozen signed artifact + conformance vectors (build/CI time ONLY)
 L4  Python canonical (kg-canonical/)   the oracle — compiles graph; NEVER ships at runtime
```

The app **never imports Python**; Swift is the only runtime. The closed on-device execution loop (decide the same graph that compiles the program that grades the rep that writes the observation) is the moat.

### 3.2 Monorepo package topology (synthesis §8.2)

```
camifit/                         (single git root — "same root, different authority zones")
├─ apps/            macos/ (SwiftUI shell), iphone/ (future)        — Swift
├─ engine/          CamiFitEngine/  (pose/rep/form; KG-agnostic)    — Swift
├─ kgkit/           Sources/KGKit/  (on-device KG serving runtime)  — Swift
├─ kg-canonical/    kg/ + graph/ + tests/ + pyproject.toml + uv.lock — PYTHON (build/CI only)
├─ contracts/       *.schema.json (DecisionReceipt / GraphOperation / FactCard / Trackability)
├─ data/            golden/candidate-assessment/ (the ONE vendored copy) + seed/ (compiled bundle)
├─ artifacts/       fitgraph.kgart.json (generated signed base) + conformance/*.vectors.json
├─ loops/           app/GOAL.md, kg/GOAL.md  (two autonomous loops, separate write scopes)
└─ Package.swift    (CamiFitEngine + KGKit + apps)
Application Support/CamiFit/KnowledgeGraph/   (runtime member state — OUTSIDE git)
```

> **DIRECTORY-LAYOUT DECISION — CLOSED (do NOT re-open):** this synthesis **keeps the existing `Sources/{CamiFitEngine,CamiFitApp,KGKit}/` and `Tests/…` layout**. The §8.2 `apps/engine/kgkit/` split is the *aspirational* target and is deferred to a separate, later structural pass. Keeping `Sources/` stable keeps every `Package.swift` `path:` unchanged and the merge diff reviewable. **Every concrete command in §6–§9 assumes this "keep `Sources/`" answer.** Do not adopt the `apps/engine/kgkit/` split during this synthesis — if you do, every downstream path (freezer `FITGRAPH=`, `Sources/KGKit/Resources/...`, artifact gate paths) becomes wrong. If a future pass DOES perform the `git mv`, the full KGKit inventory that must move is: **10 `.swift` + `README.md` + `Resources/Artifact/.gitkeep` + `Resources/Artifact/kg_artifact.v0.json`** (and `Tests/KGKitTests/` incl. `Fixtures/.gitkeep`), or `Package.swift`'s `exclude:["README.md"]` and `.copy("Resources/Artifact")` break.

**Authority zones / dependency edges (§8.2/§8.4):**
- `kg-canonical/` (Python) → compiles → `artifacts/fitgraph.kgart.json` + `conformance/*.vectors.json`. Authors graph/ontology/safety. Cannot touch Swift/UI.
- `kgkit/` (Swift) **consumes** the signed artifact + vectors; depends on no Python source. Cannot change the canonical graph.
- `engine/` (CamiFitEngine) — KG-agnostic; no dependency on KGKit decisions.
- `apps/` (Swift) → depend on `kgkit/` + `engine/`; consume `artifacts/` but never hand-edit them.
- `contracts/` — shared schemas reviewed by BOTH loops; the only true cross-language coupling point.

**Language boundary (the explicit answer):** FitGraph stays **Python** in the monorepo as `kg-canonical/`, **build/CI-time only — it never ships**. Its deterministic logic is **re-implemented (ported) in Swift** as `kgkit/` for on-device serving; the Python package remains the canonical oracle and parity source of truth. Ontology richness (OPE/COPPER/SNOMED IDs, RDF/SHACL `.ttl`) stays in Python and never crosses to the device — only labels/aliases/lattice/version-stamps/MAPS_TO-side-table ship in the artifact.

### 3.3 Immutable-base / overlay model (§4.5, §8.5)

Four graph states, each a distinct authority level:

| State | Location | Mutability |
|---|---|---|
| Canonical source graph | `kg-canonical/` (`kg/`, `graph/`, lock, compiler) | mutable by KG authors + CI only |
| **Signed base artifact** | bundled in app → copied to App Support as `base/<content_sha256>.kgart.json` | **immutable; updates are new files, never in-place** |
| Swift in-memory graph core | KGKit runtime structures | rebuilt from base + overlay at launch / after validated ops |
| **Member overlay + op log** | App Support `overlays/member/current.jsonl`, `ops/*.jsonl` | **append-only, compactable into signed local snapshots** |

In-memory view = deterministic merge `base/<sha>.kgart.json + overlays/member/current.jsonl`.

**Overlay op grammar:** `AddPreference`/`RetractPreference`, `RecordWorkoutSession`, `AttachGeneratedProgram`, `AddAliasCandidate`, `RequestClarification`, `ArchiveStaleObservation`. Each op carries `{operation_id, actor, created_at, base_artifact_sha, precondition_revision, source_span_ids[]}`.

**Hard rules:** overlay MAY add member facts/preferences/observations/local aliases/source-spans. Overlay MAY NOT edit canonical `Exercise`/`BodyRegion`/`SafetyRule`/`PART_OF`/`STRESSES`/`REQUIRES`/`VARIANT_OF`/`MAPS_TO`/severity-lattice records, and may NEVER downgrade a hard safety block, remove a required-equipment edge, or mark an unverified ontology mapping authoritative. A new canonical rule must go through `kg-canonical/` → compiler → new base artifact. A validator enforces this before any op becomes visible to KGKit. "Adaptive without letting the agent rewrite the safety brain."

---

## 4. Integration contracts (synthesis §5)

All three stamp the freeze coordinates `graph_version` / `ruleset_version` / `ontology_lock_version`; decisions/observations also stamp `constraint_fingerprint`.

### Contract 1 — Exercise Catalog (one canonical source, two projections)
A build-time `CatalogExercise` record (golden `exercises.json` 50×14 fields → keep `source_exercise_id` golden UUID + `node_id` `Type:snake_case`) projects BOTH to KG nodes/edges AND to a CamiFit `ExerciseProgram`.
- **Golden → KG edge mapping:** `muscle_groups[]`→`TARGETS` (19-vocab); `joints_loaded[]`→`STRESSES` (9-vocab, **conservative edge only** — the 7-key STRESSES safety bundle `load_level/impact_level/flexion_depth/loaded/axial_load/balance_demand/laterality` has **no upstream source** and is supplied by an authored `(movement_pattern × joint)` curation table); `movement_patterns[]`→`HAS_PATTERN` (36-vocab); `equipment_required[]`→`REQUIRES` (32-vocab, AND-subset); plus an **authored** `VARIANT_OF→ExerciseFamily` (no golden field; required because zero exercises are literally named "deadlift").
- **Trackability classification (6-tier):** `trackable_curated` / `trackable_template` / `trackable_generated` / `timer_or_manual` / `recommendation_only` / `filtered`.
- **Versioning:** stamps `graph_version` + `source_hash`.

### Contract 2 — Workout-Candidate + Decision-Receipt (KG runtime → app)
A **faithful byte-shape port** of FitGraph's live shapes — no redesign.
- **`DecisionReceipt` = 10 required fields:** `exercise_id`, `decision` (`selected|filtered|downranked`), `primary_severity` (lattice `MEDICAL_HARD_BLOCK > EQUIPMENT_HARD_BLOCK > PROMPT_EXCLUSION > MEMBER_STRONG_DISLIKE > SOFT_PENALTY > BOOST`), `reason_codes[]`, `primary_reason_code`, `graph_paths[]` (evidence strings `"src -PRED-> tgt"`), `constraint_fingerprint` (sha256[:16] over sorted-key compact JSON), `graph_version`, `ruleset_version`, `ontology_lock_version`.
- **`WorkoutCandidateResult` = `{selected_receipts[], filtered_receipts[], alternatives[]}`.**
- **`AlternativeRecord`:** `score = round(0.45·target + 0.35·pattern + 0.10·equip + 0.10·tier, 6)`, plus `score_components`, `graph_paths`; drawn ONLY from the `selected` safe pool; tie-break `(-score, id)`.
- **Proposed app envelope `WorkoutPlan`** wraps it with warmup/main/cooldown + sets/reps/rest.
- **Determinism levers (MUST be preserved in the Swift port):** explicit sorts, `round(…,6)`, sorted-key compact-JSON fingerprint, `(-score,id)` tie-break.

### Contract 3 — Member-Graph + Observation (execution → member-KG write-back) — entirely PROPOSED
Appends typed, provenance-anchored `ExercisePerformance` nodes (`completed_reps/target_reps/held_seconds/form_score/cue_codes/rom_deg_mean/tracking_quality` + `decision_fingerprint` of the authorizing receipt + `base_artifact_sha` + `overlay_revision` + version triple + `occurred_at`), plus `WorkoutSession` and rolled-up `AdherenceObservation`. Edges: `Member -HAS_PERFORMANCE-> ExercisePerformance -OF_EXERCISE-> Exercise`, each `-DERIVED_FROM-> SourceSpan` (engine trace). These land in the App Support overlay (§4.5), **NEVER in the signed base artifact**; write-back is additive member-context only — it may down-rank/boost (`SOFT_PENALTY`) but can NEVER override a `MEDICAL_HARD_BLOCK`/equipment block or relax safety.

### Cross-contract versioning rule
Every contract instance stamps the **three freeze coordinates**; every decision/observation also stamps `constraint_fingerprint`. **Known inconsistency (real, confirmed on disk):** `kg/validation.py`'s `GRAPH_VERSION="…m5-validation-v0"` flows into receipts/artifact, while `graph/exercise_kg.seed.json` self-stamps `"…m3-alternatives-v0"`; both stamps coexist. `ONTOLOGY_LOCK_VERSION` is hardcoded in `safety.py` rather than read from the lockfile. **Important for an agent regenerating the artifact:** the artifact header SHOULD read **`m5`** (from `validation.py`) — seeing `m5` is correct, NOT a bug to "fix" toward `m3`. **Proposed fix (not a merge blocker):** the build-time compiler emits ONE content-hashed artifact version derived from merged graph+ruleset+lock; all three contracts read it from the loaded artifact (single source of truth, verified by Swift on load).

---

## 5. Done vs Pending

### Done (verified on disk)
- **KGKit Swift safety core — Plan 1, parity-proven.** `Sources/KGKit/` (**10 Swift source files** + README + frozen artifact) ports the safety engine, graph store + PART_OF BFS/closure traversals, severity lattice + `DecisionReceipt`, constraint shape + NodeID normalization, safety rules + property matching, canonical-JSON fingerprint, version stamps, artifact load. Frozen artifact `kg_artifact.v0.json` = **28 nodes / 39 edges / 3 rules** (this corrects the "25/28" figure in the TARGET/plan sources — those are wrong; the plan doc on disk likely still says 25/28 and needs correcting too). **12 test suites** + `ConformanceTests.swift` proving byte-exact oracle parity. `scripts/gen_kg_conformance_vectors.py` is the freezer/oracle bridge.
- **Regimen pipeline — shared on both branches; only the authoring gate is main-only.** `Sources/CamiFitApp/Regimen/` (`RegimenBlockParser`, `WorkoutRoutine`, `RegimenStore`, `RegimenCard`) and `CodexAppServerClient.swift` exist at merge-base `9b8b8cc` and are present in the `feat/chat-regimen` working tree **right now**. Wired into `ContentView.swift` (parse each reply → render card). **The genuinely origin/main-only addition is the gate:** `CodexAppServerClient.exerciseAuthoringEnabled = false` (static) + its guard (the camifit-exercise/camifit-routine authoring instructions append only `guard exerciseAuthoringEnabled`, currently dead; the persona is returned regardless) + guard test `Tests/CamiFitAppTests/CoachAuthoringGateTests.swift::testFreeLLMExerciseAuthoringDisabledByDefault`. **Verified: the flag and the test exist ONLY on `origin/main` (commit `b6577f8`), absent from the checked-out `feat/chat-regimen`. The 3 origin/main-only commits touch exactly 2 files: `CodexAppServerClient.swift` + `CoachAuthoringGateTests.swift`.** The dormant pipeline stays present-but-dormant until a KG-backed `ProgramCompiler` authors via the same grammar + `ProgramLoader`+`FrameSignalProcessor` validation gate.

### Pending — Python-only in fitgraph, must be ported (Swift) or wrapped (build-time)
- **Resolver** (`kg/resolver.py`) — no Swift `resolve_text`; the Swift harness currently feeds pre-built `ResolvedConstraint`s. → **Plan 2 (port).** Adds on-device fuzzy beyond the Python exact/alias.
- **Alternatives** (`kg/alternatives.py`) — no Swift safe-pool scorer. → **Plan 3 (port).**
- **Member retrieval / fact cards / charts** (`kg/member_retrieval.py`) — no Swift port. → **Plan 3 (port).**
- **Assessment-import compiler** (`kg/assessment_import.py`) — stays **Python build-time**; Swift consumes only the frozen artifact (currently the 28-node seed, not the 50-exercise generated graph). → wrapped, never ported.
- **Validation / ontology pipeline** (`kg/validation.py`, ontology lock/mappings) — Python build/CI-only. Wrapped.
- **Workout generator + copilot CLIs** — Python-only references / oracle.

### The Plan roadmap (status)
- **Plan 1 — KGKit deterministic safety core — DONE (verified).** Defers `base_artifact_sha`/`overlay_revision` receipt fields (would break byte-parity) to a later plan.
- **Plan 2 — Resolver port** (`resolve_text` normalize + exact/alias + canonical cases + `only…` subset + `UnresolvedConcept` + on-device fuzzy) — PROPOSED.
- **Plan 3 — Alternatives + member retrieval port** — PROPOSED.
- **Plan 4 — Canonical compiler + 50-exercise scale-up** (grow artifact from golden `exercises.json`, precomputed closures, exact-count CI gate) — PROPOSED.
- **Plan 5 — App-local graph workspace** (App-Support base-copy + append-only member overlay + op grammar + validator forbidding canonical edits; §4.5/§8.5) — PROPOSED; "the immediate next slice."
- **Plan 6 — Monorepo package topology** (fold FitGraph in as `kg-canonical/`, authority zones + cross-language CI gates incl. `conformance-parity`; §8) — PROPOSED. **This synthesis is the execution of Plan 6.**
- Synthesis-level **Phase 0–5** (§11.2) maps Plans into product phases: P0 = monorepo+contracts (= Plan 6), P1 = canonical catalog + compiled artifact + Swift resolver/safety with parity (= Plans 1–4), P2 = candidate→ExerciseProgram compile, P3 = on-device execution + write-back (Contract 3), P4 = copilot cards+charts+brief, P5 = ontology verification + RDF/SHACL + surpass bets.

---

## 6. Merge mechanics — physically combining the repos

### 6.1 The three problems to solve simultaneously
1. **camifit divergence:** `feat/chat-regimen` (HEAD `867192c`, has KGKit + synthesis docs) vs `origin/main` (tip `a90ed8d`, has the `exerciseAuthoringEnabled=false` gate + `CoachAuthoringGateTests`). Merge-base `9b8b8cc`. **Neither branch has both** the gate and KGKit — but the regimen pipeline itself is shared. The 20 feat-only commits split into KGKit build-out (15) + synthesis/spec docs (5); the 3 origin/main-only commits are `1c1d4a0` (PR#1), `b6577f8` (the gate + guard test, 2 files), `a90ed8d` (PR#4 regimen merge). **The feat↔origin/main merge is conflict-free** (see §6.2).
2. **fitgraph has no remote** — must be imported history-preserving or its history is lost forever.
3. **candidate-assessment is duplicated** byte-identically in both host repos and must collapse to one.

### 6.2 Branch reconciliation (do this FIRST, before importing Python) — MERGE IS CONFLICT-FREE
**Decisive fact:** `git merge-tree --write-tree feat/chat-regimen origin/main` produces a **clean tree (object `f4fe2de…`) with ZERO conflict markers**, in either direction. The gate hunk on `b6577f8` (inside `CodexAppServerClient.swift`) and main's KGKit-absence do not textually overlap feat's changes, so git's 3-way merge **auto-resolves `Package.swift` and `CodexAppServerClient.swift` correctly on its own**. There is nothing to hand-edit.

**Therefore the ONLY required manual action is verification, NOT conflict resolution.** Do NOT hunt for conflicts (there are none) and do NOT hand-edit `Package.swift` or `CodexAppServerClient.swift` (git already merged them correctly — editing them risks diverging from the correct auto-merge result and introducing a regression).

Sequence inside camifit:
1. `feat/chat-regimen` is already pushed (in sync with `origin/feat/chat-regimen`, `20 0`).
2. **Create the integration branch and run the auto-merge:** `git switch -c feat/monorepo-synthesis origin/main && git merge feat/chat-regimen`. It completes cleanly (no conflicts). The resulting `Package.swift` automatically unions main's gated app with feat's re-added KGKit product/`KGKit`/`KGKitTests` targets.
3. **Assert (don't edit) that both survived:** `grep -rn "exerciseAuthoringEnabled = false" Sources/CamiFitApp/` succeeds; `ls Tests/CamiFitAppTests/CoachAuthoringGateTests.swift` and `ls Sources/KGKit/` succeed; `swift build` + `swift test` pass. **This is the gate-survives requirement, satisfied by verification alone.**

### 6.3 History-preservation choice for fitgraph → `kg-canonical/`
**Recommended default: `git subtree add` (pure git builtin) — NOT a flat copy.** Rationale (§8.7): fitgraph exists only on this machine; a flat copy discards its commit history irrecoverably. `git subtree` handles the subdirectory-prefixing itself and needs **no third-party tooling**, so it is the lower-risk default:

```
git subtree add --prefix=kg-canonical <durable-fitgraph-path> main
```

This preserves fitgraph's full commit history under `kg-canonical/` in one builtin command.

**Alternative (only if cleaner rewritten root-level history is required): `git filter-repo`.** `git filter-repo` is a **third-party tool and NOT a git builtin** — it is almost certainly not installed. If you choose this path you MUST first verify/install it: `git filter-repo --version` or `brew install git-filter-repo` / `pip install git-filter-repo`. Procedure: in a scratch clone, `git filter-repo --to-subdirectory-filter kg-canonical/`, then add the rewritten clone as a remote of camifit and `git merge --allow-unrelated-histories`. **`subtree` and `filter-repo`+`merge` are mutually exclusive procedures with different post-states — pick exactly ONE; do not interleave them.** Default to subtree to avoid the dependency. Record the choice in `loops/` GOAL docs.

Before either: confirm fitgraph's tree is clean (it is — HEAD `2597993`; `git status` should be empty) and that fitgraph is backed up (§6 step / §8 risk 3).

### 6.4 Where each repo's content maps
| Source | Destination in monorepo |
|---|---|
| `fitgraph/kg/` + `graph/` + `tests/` + `pyproject.toml` + `uv.lock` | `kg-canonical/` (history-preserved) |
| `camifit/Sources/KGKit/` | **stays `Sources/KGKit/`** (layout decision CLOSED, §3.2) |
| `camifit/Sources/CamiFitEngine/` | **stays `Sources/CamiFitEngine/`** |
| `camifit/Sources/CamiFitApp/` | **stays `Sources/CamiFitApp/`** |
| `camifit/Tests/*` | **stays `Tests/*`** |
| `candidate-assessment` payload (the ONE copy) | `data/golden/candidate-assessment/` |
| generated artifact | `Sources/KGKit/Resources/Artifact/kg_artifact.v0.json` (keep-`Sources/` layout; a top-level `artifacts/` is introduced only by the deferred §8.2 split) |
| conformance vectors | `Tests/KGKitTests/Fixtures/conformance/*.json` (likewise) |
| shared schemas | `contracts/*.schema.json` |

### 6.5 Deduplicating candidate-assessment
**Verified 2026-06-05: the four payload files (`ASSESSMENT.md`, `README.md`, `data/exercises.json`, `data/member-context.json`) are byte-identical across all three repos (`shasum` MATCH).** Both host manifests pin the same upstream commit `4b8c67246a659c26bd222079c5c7829d295acad9`, both record Fetched 2026-06-04. The two host copies differ ONLY in wrapper path + manifest:
- **fitgraph:** `docs/external/candidate-assessment/` + `SOURCE.md` (license-absence note; "implement behavior in FitGraph runtime, not by editing this copy").
- **camifit:** `docs/requirements/candidate-assessment/` + `PROVENANCE.md` ("the floor — contain it, then surpass it") + a parent `docs/requirements/README.md`.

Therefore:
- Collapse to **one** canonical copy at `data/golden/candidate-assessment/`.
- Keep ONE provenance manifest (merge the two: `SOURCE.md`'s license-absence note + `PROVENANCE.md`'s "floor, then surpass" framing) recording the pinned upstream commit + fetch date + per-file SHA-256.
- **Delete BOTH duplicate payload trees by exact path:** `docs/requirements/candidate-assessment/` (camifit-side, with `PROVENANCE.md`) AND `kg-canonical/docs/external/candidate-assessment/` (former-fitgraph-side, with `SOURCE.md`). Preserve the parent `docs/requirements/README.md` only if it has standalone value.
- **CRITICAL — `assessment_import.py` path coupling (4+ edit sites, not one).** The compiler reads the golden data via:
  - `kg/assessment_import.py` **L15** `ASSESSMENT_DIR = REPO_ROOT / "docs" / "external" / "candidate-assessment"` and **L16** `DATA_DIR = ASSESSMENT_DIR / "data"` — the functional path constant.
  - **Hardcoded provenance string literals at L205, L411, L739** (`"docs/external/candidate-assessment/data/exercises.json"` / `…/member-context.json`) baked into `source_file`/provenance properties written **into the generated graph** — cosmetic-but-audited; if left stale the compiler runs but stamps wrong provenance paths silently.
  - `SOURCE_SNAPSHOT_COMMIT` at **L20** (must still equal `4b8c672…`).
  - **`REPO_ROOT` derivation problem:** `ASSESSMENT_DIR` is computed relative to `REPO_ROOT` (the module's `Path(__file__).parents[N]` root). After folding fitgraph under `kg-canonical/`, `REPO_ROOT` resolves to the `kg-canonical/` root, but the new golden lives at the **monorepo root** `data/golden/candidate-assessment/` — two levels up from `kg-canonical/kg/`. **Read how `REPO_ROOT` is actually derived and set the new path explicitly/absolutely (anchored at the monorepo root, e.g. `REPO_ROOT.parent / "data" / "golden" / "candidate-assessment"`); do NOT assume the old relative path "just works" after the move.** Update all four sites (the constant + three provenance literals) so the artifact's `source_file` fields match the new golden path.
  - After the edits, re-run `python -m kg.assessment_import` and confirm the conformance summary still hits exact counts (50/19/9/36/32 + full Jordan).
- No content reconciliation is needed — only path + manifest consolidation.

### 6.6 Package.swift after the merge
**git produces the correct `Package.swift` automatically** (the merge is conflict-free; main's gate-side does not touch `Package.swift`, and feat re-adds the KGKit product/`KGKit`/`KGKitTests` targets that main lacks). The merged manifest will declare `CamiFitEngine` + `KGKit` (product + target with `exclude:["README.md"]` and `.copy("Resources/Artifact")`) + `KGKitTests` (dep `[KGKit]`, `.copy("Fixtures")`) + `CamiFitApp` + the three test targets. **Verify this — do not hand-write or hand-edit it.** Because the layout decision is CLOSED at "keep `Sources/`," no `path:` edits are needed.

---

## 7. Conformance & parity

The Python `kg/` oracle is canonical truth; the Swift `kgkit/` port must reproduce its receipts **byte-for-byte**, enforced as a hard CI gate. "Determinism is the contract that lets the brain move from server to phone without behavioral drift."

- **Vector format** (`Tests/KGKitTests/Fixtures/conformance/*.json`, one per surface: `resolve`, `safety`, `alternatives`, `member_retrieval`): `{harness, artifact_content_sha256, vectors:[{id, input, expected}]}`. Each file pins `artifact_content_sha256` so a stale artifact can't validate against fresh vectors. Today's realized version lives at `Tests/KGKitTests/Fixtures/conformance/safety_vectors.json` (4 scenarios: knee_restriction, no_barbell, exclude_deadlifts, clean × all exercises).
- **The gate** `conformance-parity` = `swift test --filter ConformanceTests` (`Tests/KGKitTests/ConformanceTests.swift`): Swift loads the SAME signed artifact, replays each vector, asserts field-by-field equality. **Exact** for strings/enums/arrays AND **ordering** (`graph_paths` order, a→b→c reason-generator order, `(-score,id)` tie-break — all load-bearing); floats compare at the oracle's `round(…,6)`.
- **The canary = `constraint_fingerprint`:** `sha256[:16]` over `json.dumps(payload, sort_keys=True, separators=(",",":"))` (ensure_ascii, unescaped `/`), field set `{available_equipment sorted, constraints[{type,value,hard,negated,source_text}], exercise_id}`. `Sources/KGKit/CanonicalJSON.swift` hand-reimplements Python's escaping to guarantee parity. Any fingerprint mismatch fails the build before any behavioral diff is inspected.
- **Determinism invariants preserved verbatim across the port:** explicit sorts (nodes by id, closure edges by source/target, candidates by id), BFS PART_OF path with edges sorted by target, `round(…,6)`, sorted-key compact-JSON fingerprint.

**How to preserve parity through the merge:**
1. **Record the baseline SHAs NOW (pre-merge), so "unchanged" is verifiable later:** `shasum -a 256 Sources/KGKit/Resources/Artifact/kg_artifact.v0.json` and `shasum -a 256 Tests/KGKitTests/Fixtures/conformance/safety_vectors.json`. Pin both values in the integration branch's notes — they are the regeneration targets.
2. **Do not edit `kg_artifact.v0.json` or `safety_vectors.json` by hand** during the merge — they are generated outputs.
3. After folding Python into `kg-canonical/`, **verify the freezer's `FITGRAPH=` contract before invoking** (read the script's `sys.path` logic; it inserts `FITGRAPH` then `import kg`, so `FITGRAPH` must point at the directory **containing** the `kg/` package — i.e. `kg-canonical/`, NOT `kg-canonical/kg/`; a one-level-off path yields `ModuleNotFoundError: kg`, which is NOT corruption). Re-run `scripts/gen_kg_conformance_vectors.py` with `FITGRAPH=$(pwd)/kg-canonical`; confirm it regenerates the identical artifact + vectors (content SHAs match the §7.1 baselines) — this proves the move didn't perturb the oracle.
4. Run `swift test --filter ConformanceTests` green as the merge's acceptance gate.
5. Wire the full gate set: `kg-python` (pytest in `kg-canonical/`), `kg-validation` (`python -m kg.validation`), `artifact-build` (artifacts regenerated from source, not hand-edited — fail if `git diff` on the generated outputs is non-empty after regen; **the gate path depends on the layout decision** — in the keep-`Sources/` layout that path is `git diff --exit-code Sources/KGKit/Resources/ Tests/KGKitTests/Fixtures/conformance/`, NOT a top-level `artifacts/` which does not exist under this layout), `swift-test`, `conformance-parity`, `contracts-compat` (schema validation over fixtures/vectors/app-generated blocks).

---

## 8. Risks & open decisions

1. **Directory layout — DECIDED, not open.** Keep the existing `Sources/{CamiFitEngine,CamiFitApp,KGKit}/` for this synthesis; the §8.2 `apps/engine/kgkit/` split is a separate later pass. **Do not re-open this** — every concrete command in §6–§9 depends on the keep-`Sources/` answer; adopting the split mid-synthesis breaks every downstream path.
2. **History import method (OPEN — pick one):** `git subtree add --prefix=kg-canonical` (builtin, default, one command) vs `git filter-repo --to-subdirectory-filter` + `merge --allow-unrelated-histories` (third-party, must be installed first, cleaner rewritten history). Both preserve history; they are mutually exclusive. **A flat copy is NOT acceptable** (loses fitgraph's only history). Default to subtree.
3. **fitgraph has no backup remote — high risk.** Before any rewrite, back it up to a **durable** path (NOT `/tmp`, which is wiped on reboot — for the one repo that exists nowhere else, a reboot between backup and a botched import loses everything). Write `git bundle create ~/Developer/fitgraph-backup-2026-06-05.bundle --all` AND push to a real private remote; treat the bundle as secondary.
4. **`assessment_import.py` path coupling (4+ sites):** dedup of candidate-assessment breaks the compiler's hardcoded `docs/external/candidate-assessment/...` path constant AND three provenance string literals AND the `REPO_ROOT`-relative resolution (§6.5). Update all sites and re-verify exact-count conformance, else the build-time graph generation silently breaks or stamps stale provenance.
5. **The gate-survives requirement:** the merge MUST land both KGKit and the `exerciseAuthoringEnabled=false` gate + `CoachAuthoringGateTests`. The merge is conflict-free and git unions both automatically — the risk is NOT a dropped conflict but an agent **needlessly hand-editing** a file git already merged. Assert both post-merge by verification; do not edit.
6. **Version-stamp inconsistency** (`m5` vs `m3-alternatives-v0`, hardcoded `ONTOLOGY_LOCK_VERSION`): real and confirmed; not a merge blocker. The artifact header SHOULD read `m5` — do not "fix" it toward `m3`. Track the compiler-single-source-of-truth fix (§4 versioning rule) so contracts read one content-hashed version.
7. **Artifact scale gap:** the shipping Swift artifact is the 28-node hand-curated seed; the 50-exercise generated graph lives only in `graph/generated/` (212 nodes/512 edges exercise, 77/97 member). Plan 4 scale-up is required before the product satisfies the candidate-assessment 50-exercise floor at runtime. Not a merge blocker.
8. **macOS 26.0 platform pin / toolchain — verify FIRST.** `Package.swift` pins `macOS 26.0`. Before any merge, run a Phase-0 check: `swift --version` + a trial `swift build` on the **current** tree, so a toolchain mismatch is discovered up front, not at the acceptance gate (where it would otherwise loop). (Toolchain support for macOS 26.0 could not be verified here — treat as a precondition.)

---

## 9. Concrete step-by-step execution plan

> Run from `/Users/kelly/Developer/camifit` unless noted. Commit/branch facts as of 2026-06-05. **This plan assumes the CLOSED keep-`Sources/` layout decision (§3.2).**

**Phase 0 — Toolchain precondition**
0. `swift --version`; trial `swift build` on the current `feat/chat-regimen` tree. If it fails on the `macOS 26.0` pin, resolve the toolchain BEFORE proceeding (do not discover this at the acceptance gate).

**Phase A — Safeguard (irreversibility insurance)**
1. `cd /Users/kelly/Developer/fitgraph` → assert clean: `git status --porcelain` should be empty (HEAD `2597993`; the in-flight test work is already committed — this is now a no-op assertion, not a commit step). Back it up DURABLY: `git bundle create ~/Developer/fitgraph-backup-2026-06-05.bundle --all` AND push to a new private remote. (fitgraph has no remote — this is mandatory; do NOT use `/tmp`.)
2. `cd /Users/kelly/Developer/camifit` → `git tag pre-monorepo-freeze` on current `feat/chat-regimen` HEAD `867192c`. `feat/chat-regimen` is already pushed (in sync with `origin/feat/chat-regimen`, `20 0`).
3. **Record parity baselines:** `shasum -a 256 Sources/KGKit/Resources/Artifact/kg_artifact.v0.json` and `shasum -a 256 Tests/KGKitTests/Fixtures/conformance/safety_vectors.json` — pin both as regeneration targets.

**Phase B — Reconcile camifit branches (CONFLICT-FREE; verify, don't resolve)**
4. `git fetch origin && git switch -c feat/monorepo-synthesis origin/main`.
5. `git merge feat/chat-regimen` — **this auto-resolves with zero conflicts** (`merge-tree` proves a clean tree `f4fe2de…`). git produces the correct unioned `Package.swift` and `CodexAppServerClient.swift` automatically. **Do NOT hand-edit either file.**
6. **Assert both survive (verification only):** `grep -rn "exerciseAuthoringEnabled = false" Sources/CamiFitApp/` succeeds; `ls Tests/CamiFitAppTests/CoachAuthoringGateTests.swift` and `ls Sources/KGKit/` succeed; `swift build` and `swift test` pass.

**Phase C — Import fitgraph history → `kg-canonical/`**
7. **Default (builtin, recommended):** `git subtree add --prefix=kg-canonical ~/Developer/fitgraph main`. (Alternative, ONLY if you first ran `git filter-repo --version`/installed it: filter-repo a scratch clone with `--to-subdirectory-filter kg-canonical/`, then `git merge --allow-unrelated-histories`. Pick exactly one path.) fitgraph's full history now lives under `kg-canonical/`.
8. Verify Python still runs: `cd kg-canonical && uv sync --dev && uv run pytest` green; `uv run python -m kg.validation` exits 0.

**Phase D — Deduplicate candidate-assessment**
9. Move ONE copy to `data/golden/candidate-assessment/` (payload byte-identical across sources — verified). Merge the two manifests (`SOURCE.md` + `PROVENANCE.md`) into one provenance file pinning commit `4b8c672…` + fetch date 2026-06-04 + SHA-256s.
10. Delete BOTH redundant payload trees by exact path: `docs/requirements/candidate-assessment/` (camifit) AND `kg-canonical/docs/external/candidate-assessment/` (former fitgraph). Preserve `docs/requirements/README.md` only if standalone-valuable.
11. **Update `kg-canonical/kg/assessment_import.py` at all 4+ sites (§6.5):** the `ASSESSMENT_DIR` constant (L15/L16, anchored explicitly at the monorepo-root `data/golden/candidate-assessment/` — verify `REPO_ROOT` derivation first), the three provenance string literals (L205/L411/L739), and confirm `SOURCE_SNAPSHOT_COMMIT` (L20) still equals `4b8c672…`. Re-run `uv run python -m kg.assessment_import` → confirm conformance summary `status:pass` with exact counts (50/19/9/36/32 + full Jordan).

**Phase E — Wire the build/CI seam**
12. **Confirm the freezer's `FITGRAPH=` contract** (it must point at the dir containing `kg/`, i.e. `kg-canonical/`), then re-run: `FITGRAPH=$(pwd)/kg-canonical python scripts/gen_kg_conformance_vectors.py`. Confirm `Sources/KGKit/Resources/Artifact/kg_artifact.v0.json` and `Tests/KGKitTests/Fixtures/conformance/safety_vectors.json` regenerate identically — **content SHAs match the Phase-A step-3 baselines**.
13. Run the parity gate: `swift test --filter ConformanceTests` → green (byte-exact, including `constraint_fingerprint`).
14. Add CI gates: `kg-python` (pytest), `kg-validation`, `artifact-build` (regenerate; fail if `git diff --exit-code Sources/KGKit/Resources/ Tests/KGKitTests/Fixtures/conformance/` is dirty — keep-`Sources/` layout path, NOT a top-level `artifacts/`), `swift-test`, `conformance-parity`, `contracts-compat`.
15. (Deferred per §3.2 / §8 decision 1 — do NOT do this in this synthesis) the §8.2 `git mv` into `apps/engine/kgkit/` is a separate later pass.

**Phase F — Land**
16. Full green: `swift build`, `swift test` (incl. KGKit + CoachAuthoringGate + Conformance), `uv run pytest` in `kg-canonical/`. Confirm the gate flag is still `false` and KGKit is present.
17. Open the PR `feat/monorepo-synthesis → main`. Body must note: history-preserved fitgraph import, candidate-assessment dedup + `assessment_import.py` path update, gate+KGKit coexistence (auto-merged, conflict-free), green conformance-parity.

**Acceptance (= "done", from §1):** one root; fitgraph history preserved; gate + KGKit coexist; `swift build`/`swift test`/`pytest` green; `conformance-parity` byte-exact; one deduped golden copy; CI gate set wired.

---

### Key absolute paths
- Canonical synthesis spec: `/Users/kelly/Developer/camifit/docs/design/2026-06-04-camifit-fitgraph-synthesis.md`
- KGKit plan (NOTE: likely still states the wrong "25/28" artifact counts — correct to 28/39/3): `/Users/kelly/Developer/camifit/docs/superpowers/plans/2026-06-04-swift-kgkit-safety-core.md`
- Swift safety core: `/Users/kelly/Developer/camifit/Sources/KGKit/` (10 Swift source files + README + frozen artifact + `.gitkeep`)
- Frozen artifact: `/Users/kelly/Developer/camifit/Sources/KGKit/Resources/Artifact/kg_artifact.v0.json` (28 nodes / 39 edges / 3 rules)
- Freezer/oracle bridge: `/Users/kelly/Developer/camifit/scripts/gen_kg_conformance_vectors.py`
- Parity gate: `/Users/kelly/Developer/camifit/Tests/KGKitTests/ConformanceTests.swift`
- Golden vectors: `/Users/kelly/Developer/camifit/Tests/KGKitTests/Fixtures/conformance/safety_vectors.json`
- Authoring gate (origin/main only): `/Users/kelly/Developer/camifit/Sources/CamiFitApp/CodexAppServerClient.swift` (`exerciseAuthoringEnabled = false`) + `/Users/kelly/Developer/camifit/Tests/CamiFitAppTests/CoachAuthoringGateTests.swift`
- Compiler with path coupling (4+ edit sites): `/Users/kelly/Developer/fitgraph/kg/assessment_import.py` (→ `kg-canonical/kg/assessment_import.py`), L15/L16 (`ASSESSMENT_DIR`/`DATA_DIR`), L20 (`SOURCE_SNAPSHOT_COMMIT`), L205/L411/L739 (provenance literals)
- Python oracle: `/Users/kelly/Developer/fitgraph/kg/` (13 modules) + `/Users/kelly/Developer/fitgraph/graph/` (seeds + `generated/`) + `pyproject.toml` + `uv.lock`
- Golden spec source: `/Users/kelly/Developer/candidate-assessment/` (HEAD `4b8c672…`, the ONLY pushed/backed-up repo of the three)
- fitgraph host-vendor copy: `/Users/kelly/Developer/fitgraph/docs/external/candidate-assessment/` (`SOURCE.md`); camifit host-vendor copy: `/Users/kelly/Developer/camifit/docs/requirements/candidate-assessment/` (`PROVENANCE.md`) + parent `docs/requirements/README.md`

### Critical commit/branch facts
- camifit: branch `feat/chat-regimen` HEAD `867192c`; `origin/main` tip `a90ed8d`; merge-base `9b8b8cc`; ahead 20 / behind 3; **fully pushed to `origin/feat/chat-regimen` (`20 0`)**. KGKit + synthesis docs are feat-only; the gate (`b6577f8`, 2 files) + regimen merge (`a90ed8d`) are origin/main-only. **Neither branch has both KGKit and the gate; the regimen pipeline is shared from `9b8b8cc`. The feat↔origin/main merge is CONFLICT-FREE (`merge-tree` → clean tree `f4fe2de…`).**
- fitgraph: branch `main` HEAD **`2597993`** (in-flight test work already committed); working tree **CLEAN**; **NO remote — exists only on this machine.**
- candidate-assessment: branch `main` HEAD `4b8c67246a659c26bd222079c5c7829d295acad9`; clean; pushed; vendored byte-identically into both host repos (verified MATCH on all four payload files 2026-06-05).