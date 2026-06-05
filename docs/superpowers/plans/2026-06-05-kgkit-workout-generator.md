# KGKit Workout Generator Swift Port — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port FitGraph's `kg/workout_generator.py` `generate_workout` to Swift `KGKit` — the on-device **Workout Generator (surface A)** that composes resolve → safety → alternatives into a structured warmup/main/cooldown plan with sets/reps/rest and provenance, proven against the live Python oracle.

**Architecture:** Completes the safety-core + resolver/alternatives slices. The generator is a pure **exercise-side composition**: `resolveText(prompt)` + caller-supplied member constraints → candidate filtering → `SafetyEngine.evaluateCandidates` → `Alternatives.buildWorkoutCandidates` → section/prescription assembly. The member-graph derivation (injuries/equipment) is **deliberately NOT ported** — it is the Codex agent's member/overlay lane; this generator takes `availableEquipment` + `memberConstraints` as parameters, so it touches no member-loading code.

**Tech Stack:** Swift 5.9 / SwiftPM, XCTest, Foundation. Python 3 + FitGraph (`/Users/kelly/Developer/fitgraph`) at vector-generation time only.

---

## Scope & non-goals

**In scope:** `WorkoutGenerator.generateWorkout` (the exercise-side composition), its `WorkoutPlan`/`Prescription` output types, candidate filtering, section/prescription logic, and a workout conformance harness.

**Out of scope (Codex's lane — do NOT touch):** reading the member graph for injuries/equipment (`_active_injury_constraints`, `_equipment_from_member`), member-overlay, copilot/member-retrieval. Those derive the `availableEquipment` + `memberConstraints` this generator consumes.

**Determinism (preserve exactly):** `nodesByType("Exercise")` is id-sorted; the candidate keyword filter; the main-section sort by `(-priority_score, id)` (Python's stable sort over an id-sorted list); the warmup=mobility[0..2]/main[0..5]/cooldown=mobility[2..4] slicing; the prescription rules. Source: `/Users/kelly/Developer/fitgraph/kg/workout_generator.py`.

## File structure

| File | Responsibility |
|---|---|
| `Sources/KGKit/WorkoutGenerator.swift` | `WorkoutPlan`/`Prescription`/`ExerciseSummary`/`AlternativeSummary` + `WorkoutGenerator` enum (helpers + `generateWorkout`). |
| `scripts/gen_kg_conformance_vectors.py` (modify) | Emit `workout_vectors.json` from live `generate_workout`. |
| `Tests/KGKitTests/Fixtures/conformance/workout_vectors.json` (generated) | Golden vectors. |
| `Tests/KGKitTests/{WorkoutGeneratorTests,WorkoutConformanceTests}.swift` | Unit + parity tests. |

---

### Task G1: Types, helpers, and section assembly

**Files:** Create `Sources/KGKit/WorkoutGenerator.swift`; Create `Tests/KGKitTests/WorkoutGeneratorTests.swift`.

Port `_node_value`/`LOWER_BODY_TARGETS`/`_is_lower_body_candidate`/`_candidate_ids`/`_prescription`/`_workout_sections` plus the output value types. Reads `priority_score`/`is_duration`/`is_reps`/`supports_weight` from node properties.

- [ ] **Step 1: Write the failing test** `Tests/KGKitTests/WorkoutGeneratorTests.swift`:
```swift
import XCTest
@testable import KGKit

final class WorkoutGeneratorTests: XCTestCase {
    private func graph() throws -> LocalGraph { try LocalGraph(artifact: try ArtifactLoader.bundled()) }

    func testCandidateIdsLowerBodyFilter() throws {
        let g = try graph()
        let all = g.nodesByType("Exercise").map { $0.id }
        let lower = WorkoutGenerator.candidateIds("lower body / knee focus", g)
        XCTAssertFalse(lower.isEmpty)
        XCTAssertTrue(lower.allSatisfy { all.contains($0) })
        // Every lower-body candidate hits a lower-body target or a "lower" pattern.
        XCTAssertTrue(lower.allSatisfy { WorkoutGenerator.isLowerBodyCandidate(g, $0) })
        // A non-keyword prompt returns the full id-sorted set.
        XCTAssertEqual(WorkoutGenerator.candidateIds("anything", g), all)
    }

    func testPrescriptionRepsVsDuration() throws {
        let g = try graph()
        // Pick any rep-based exercise and any duration-only one if present; assert shape.
        let anyExercise = g.nodesByType("Exercise").first!.id
        let p = WorkoutGenerator.prescription(g, anyExercise, "main")
        // main section: either reps-style (sets/reps/rest) or duration-style (duration/rest).
        if p.sets != nil {
            XCTAssertEqual(p.sets, 3); XCTAssertEqual(p.restSeconds, 75)
            XCTAssertNotNil(p.reps); XCTAssertNil(p.durationSeconds)
        } else {
            XCTAssertEqual(p.durationSeconds, 60); XCTAssertEqual(p.restSeconds, 30)
            XCTAssertNil(p.reps)
        }
        XCTAssertEqual(p.exerciseID, anyExercise)
    }

    func testWorkoutSectionsSlicingAndSort() throws {
        let g = try graph()
        // Build a fake selected set of >5 known exercise ids to exercise main[:5] + sort.
        let ids = g.nodesByType("Exercise").map { $0.id }
        let selected = ids.prefix(7).map { id in
            DecisionReceipt(exerciseID: id, decision: "selected", primarySeverity: "BOOST",
                            reasonCodes: ["PASSED_SAFETY"], primaryReasonCode: "PASSED_SAFETY",
                            graphPaths: [], constraintFingerprint: "f", graphVersion: "v",
                            rulesetVersion: "v", ontologyLockVersion: "v") }
        let s = WorkoutGenerator.workoutSections(g, Array(selected))
        XCTAssertLessThanOrEqual(s.main.count, 5)
        // main is sorted by descending priority_score (ties by id).
        let scores = s.main.map { WorkoutGenerator.priorityScore(g, $0.exerciseID) }
        XCTAssertEqual(scores, scores.sorted(by: >))
    }
}
```

- [ ] **Step 2: Run, verify it fails** (`cannot find 'WorkoutGenerator' in scope`): `swift test --disable-sandbox --filter WorkoutGeneratorTests`

- [ ] **Step 3: Implement** `Sources/KGKit/WorkoutGenerator.swift`:
```swift
import Foundation

public struct Prescription: Equatable, Sendable {
    public let exerciseID: String
    public let name: String
    public let sets: Int?
    public let reps: String?
    public let restSeconds: Int?
    public let durationSeconds: Int?
}

public struct ExerciseSummary: Equatable, Sendable {
    public let exerciseID: String
    public let name: String
    public let decision: String
    public let reasonCodes: [String]
}

public struct AlternativeSummary: Equatable, Sendable {
    public let filteredExerciseID: String
    public let alternativeExerciseID: String
    public let score: Double
}

public struct WorkoutPlan: Equatable, Sendable {
    public let memberID: String
    public let prompt: String
    public let timeWindowMinutes: Int
    public let availableEquipment: [String]
    public let resolvedConstraints: [ResolvedConstraint]
    public let unresolvedConcepts: [ResolvedConstraint]
    public let warmup: [Prescription]
    public let main: [Prescription]
    public let cooldown: [Prescription]
    public let selectedExercises: [ExerciseSummary]
    public let filteredExercises: [ExerciseSummary]
    public let alternatives: [AlternativeSummary]
}

/// Exercise-side workout generator (kg/workout_generator.py generate_workout).
/// Member-graph derivation is intentionally external (caller passes availableEquipment + memberConstraints).
public enum WorkoutGenerator {
    static let lowerBodyTargets: Set<String> = [
        "MuscleGroup:glutes", "MuscleGroup:quads", "MuscleGroup:hamstrings", "MuscleGroup:calves",
        "MuscleGroup:hip_flexors", "MuscleGroup:hip_adductors", "MuscleGroup:lower_back",
    ]

    static func label(_ g: LocalGraph, _ id: String) -> String { g.nodes[id]?.label ?? id }

    static func priorityScore(_ g: LocalGraph, _ id: String) -> Double {
        if let n = g.nodes[id], case let .double(v)? = n.properties["priority_score"] { return v }
        return 0.0
    }
    private static func boolProp(_ g: LocalGraph, _ id: String, _ key: String) -> Bool {
        if let n = g.nodes[id], case let .bool(v)? = n.properties[key] { return v }
        return false
    }

    public static func isLowerBodyCandidate(_ g: LocalGraph, _ id: String) -> Bool {
        let targets = Set(g.outgoing(id, predicate: "TARGETS").map { $0.target })
        let patterns = g.outgoing(id, predicate: "HAS_PATTERN").map { label(g, $0.target).lowercased() }
        return !targets.isDisjoint(with: lowerBodyTargets) || patterns.contains { $0.contains("lower") }
    }

    public static func candidateIds(_ prompt: String, _ g: LocalGraph) -> [String] {
        let exerciseIDs = g.nodesByType("Exercise").map { $0.id }   // id-sorted
        let n = prompt.lowercased()
        if n.contains("lower") || n.contains("leg") || n.contains("knee") {
            return exerciseIDs.filter { isLowerBodyCandidate(g, $0) }
        }
        if n.contains("pec") || n.contains("chest") {
            return exerciseIDs.filter { id in
                g.outgoing(id, predicate: "TARGETS").contains { $0.target == "MuscleGroup:chest" }
            }
        }
        return exerciseIDs
    }

    public static func prescription(_ g: LocalGraph, _ id: String, _ section: String) -> Prescription {
        let name = label(g, id)
        if boolProp(g, id, "is_duration") && !boolProp(g, id, "is_reps") {
            return Prescription(exerciseID: id, name: name, sets: nil, reps: nil,
                                restSeconds: 30, durationSeconds: section == "warmup" ? 40 : 60)
        }
        let warmCool = (section == "warmup" || section == "cooldown")
        return Prescription(exerciseID: id, name: name,
                            sets: warmCool ? 2 : 3,
                            reps: boolProp(g, id, "supports_weight") ? "8-10" : "10-12",
                            restSeconds: warmCool ? 45 : 75, durationSeconds: nil)
    }

    public static func workoutSections(_ g: LocalGraph, _ selected: [DecisionReceipt])
        -> (warmup: [Prescription], main: [Prescription], cooldown: [Prescription]) {
        let selectedIDs = selected.map { $0.exerciseID }
        func isMobility(_ id: String) -> Bool {
            g.outgoing(id, predicate: "HAS_PATTERN").contains { e in
                let l = label(g, e.target).lowercased()
                return l.contains("mobility") || l.contains("regen") || l.contains("yoga")
            }
        }
        let mobility = selectedIDs.filter(isMobility)
        let mobilitySet = Set(mobility)
        var mainIDs = selectedIDs.filter { !mobilitySet.contains($0) }
        mainIDs.sort { a, b in
            let pa = priorityScore(g, a), pb = priorityScore(g, b)
            if pa != pb { return pa > pb }
            return a < b   // stable: pre-sort order is id-sorted
        }
        let warmupIDs = Array(mobility.prefix(2))
        let mainPick = Array((mainIDs.isEmpty ? selectedIDs : mainIDs).prefix(5))
        let cooldownIDs = Array(mobility.dropFirst(2).prefix(2))
        return (warmupIDs.map { prescription(g, $0, "warmup") },
                mainPick.map { prescription(g, $0, "main") },
                cooldownIDs.map { prescription(g, $0, "cooldown") })
    }
}
```

- [ ] **Step 4: Run, verify it passes** (3 tests): `swift test --disable-sandbox --filter WorkoutGeneratorTests`

- [ ] **Step 5: Commit**
```bash
git add Sources/KGKit/WorkoutGenerator.swift Tests/KGKitTests/WorkoutGeneratorTests.swift
git commit -m "feat(kgkit): workout-generator types, candidate filtering, prescription + sections"
```

---

### Task G2: `generateWorkout` composition + assembly

**Files:** Modify `Sources/KGKit/WorkoutGenerator.swift` (add `generateWorkout` to the enum); Create `Tests/KGKitTests/WorkoutComposeTests.swift`.

Compose resolve + member constraints + safety + alternatives + sections into the `WorkoutPlan`.

- [ ] **Step 1: Write the failing test** `Tests/KGKitTests/WorkoutComposeTests.swift`:
```swift
import XCTest
@testable import KGKit

final class WorkoutComposeTests: XCTestCase {
    private func engine() throws -> SafetyEngine {
        let a = try ArtifactLoader.bundled()
        return SafetyEngine(graph: try LocalGraph(artifact: a), rules: a.safetyRules)
    }

    func testGenerateLowerBodyAvoidingKnee() throws {
        let e = try engine()
        // Member layer (Codex's lane) would supply these; here we pass them directly:
        let knee = ResolvedConstraint(constraintType: "BodyRegion", value: "left_knee", hard: true,
                                      sourceText: "left knee active injury", safetyBehavior: "block_if_safety_critical")
        let plan = try WorkoutGenerator.generateWorkout(
            engine: e, prompt: "lower body, knee-safe", minutes: 50,
            availableEquipment: ["Equipment:dumbbell", "Equipment:kettlebell", "Equipment:yoga_mat"],
            memberConstraints: [knee])
        XCTAssertEqual(plan.timeWindowMinutes, 50)
        XCTAssertEqual(plan.availableEquipment, ["Equipment:dumbbell", "Equipment:kettlebell", "Equipment:yoga_mat"])
        // The knee restriction must filter at least one exercise, and none selected is also filtered.
        let selected = Set(plan.selectedExercises.map { $0.exerciseID })
        let filtered = Set(plan.filteredExercises.map { $0.exerciseID })
        XCTAssertTrue(selected.isDisjoint(with: filtered))
        XCTAssertLessThanOrEqual(plan.main.count, 5)
        // Every alternative is drawn from the selected pool.
        for alt in plan.alternatives { XCTAssertTrue(selected.contains(alt.alternativeExerciseID)) }
        // The member constraint is carried in resolvedConstraints.
        XCTAssertTrue(plan.resolvedConstraints.contains { $0.value == "left_knee" })
    }
}
```

- [ ] **Step 2: Run, verify it fails** (`has no member 'generateWorkout'`): `swift test --disable-sandbox --filter WorkoutComposeTests`

- [ ] **Step 3: Add to the `WorkoutGenerator` enum:**
```swift
    /// Port of generate_workout (exercise-side): resolve(prompt) + memberConstraints -> safety -> alternatives -> sections.
    public static func generateWorkout(engine: SafetyEngine, prompt: String, minutes: Int,
                                       availableEquipment: [String], memberConstraints: [ResolvedConstraint],
                                       memberID: String = "Member:jordan") throws -> WorkoutPlan {
        let g = engine.graph
        let promptConstraints = try Resolver.resolveText(prompt, graph: g)
        let constraints = promptConstraints + memberConstraints
        let candidates = candidateIds(prompt, g)
        let receipts = try engine.evaluateCandidates(candidates, availableEquipment: availableEquipment,
                                                     constraints: constraints)
        let result = try Alternatives.buildWorkoutCandidates(receipts, availableEquipment: availableEquipment, graph: g)
        let sections = workoutSections(g, result.selectedReceipts)
        func summary(_ r: DecisionReceipt) -> ExerciseSummary {
            ExerciseSummary(exerciseID: r.exerciseID, name: label(g, r.exerciseID),
                            decision: r.decision, reasonCodes: r.reasonCodes)
        }
        return WorkoutPlan(
            memberID: memberID, prompt: prompt, timeWindowMinutes: minutes,
            availableEquipment: availableEquipment.sorted(),
            resolvedConstraints: constraints,
            unresolvedConcepts: constraints.filter { $0.constraintType == "UnresolvedConcept" },
            warmup: sections.warmup, main: sections.main, cooldown: sections.cooldown,
            selectedExercises: result.selectedReceipts.map(summary),
            filteredExercises: result.filteredReceipts.map(summary),
            alternatives: result.alternatives.map {
                AlternativeSummary(filteredExerciseID: $0.filteredExerciseID,
                                   alternativeExerciseID: $0.alternativeExerciseID, score: $0.score)
            })
    }
```

- [ ] **Step 4: Run, verify it passes:** `swift test --disable-sandbox --filter WorkoutComposeTests`

- [ ] **Step 5: Commit**
```bash
git add Sources/KGKit/WorkoutGenerator.swift Tests/KGKitTests/WorkoutComposeTests.swift
git commit -m "feat(kgkit): generateWorkout composition (resolve+safety+alternatives -> structured plan)"
```

---

### Task G3: Workout conformance vectors + README + full gate

**Files:** Modify `scripts/gen_kg_conformance_vectors.py`; generate `Tests/KGKitTests/Fixtures/conformance/workout_vectors.json`; Create `Tests/KGKitTests/WorkoutConformanceTests.swift`; Modify `Sources/KGKit/README.md`.

- [ ] **Step 1: Extend the generator.** Add BEFORE `if __name__`:
```python
from kg.workout_generator import generate_workout, _active_injury_constraints  # noqa: E402
from kg.graph_store import load_member_graph  # noqa: E402

WORKOUT_VECTORS = REPO / "Tests/KGKitTests/Fixtures/conformance/workout_vectors.json"

WORKOUT_SCENARIOS = [
    {"prompt": "lower body, knee-safe", "minutes": 50},
    {"prompt": "full body strength", "minutes": 50},
    {"prompt": "chest and pecs", "minutes": 40},
]


def emit_workout_vectors() -> None:
    graph = load_local_graph(FITGRAPH / "graph" / "exercise_kg.seed.json")
    member_graph = load_member_graph(FITGRAPH / "graph" / "member_kg.seed.json")
    member_id = "Member:jordan"
    member_constraints = _active_injury_constraints(member_id, member_graph, graph)
    vectors = []
    for sc in WORKOUT_SCENARIOS:
        out = generate_workout(member_id=member_id, prompt=sc["prompt"], minutes=sc["minutes"],
                               graph=graph, member_graph=member_graph)
        vectors.append({
            "prompt": sc["prompt"], "minutes": sc["minutes"],
            "available_equipment": out["available_equipment"],
            "member_constraints": [
                {"constraint_type": c.constraint_type, "value": c.value, "hard": c.hard,
                 "negated": c.negated, "laterality": c.laterality, "graph_paths": list(c.graph_paths),
                 "source_text": c.source_text, "safety_behavior": c.safety_behavior,
                 "resolution_status": c.resolution_status} for c in member_constraints
            ],
            "expected": {
                "warmup": out["workout"]["warmup"], "main": out["workout"]["main"],
                "cooldown": out["workout"]["cooldown"],
                "selected_ids": [r["exercise_id"] for r in out["selected_exercises"]],
                "filtered_ids": [r["exercise_id"] for r in out["filtered_exercises"]],
                "alternatives": [{"filtered_exercise_id": a["filtered_exercise_id"],
                                  "alternative_exercise_id": a["alternative_exercise_id"],
                                  "score": a["score"]} for a in out["alternatives"]],
            },
        })
    WORKOUT_VECTORS.parent.mkdir(parents=True, exist_ok=True)
    WORKOUT_VECTORS.write_text(json.dumps({"vectors": vectors}, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {WORKOUT_VECTORS.relative_to(REPO)}: {len(vectors)} workout vectors")
```
Add `emit_workout_vectors()` to the `if __name__ == "__main__":` block (after the existing calls). `load_local_graph`, `FITGRAPH`, `REPO`, `json` are already in scope.

- [ ] **Step 2: Generate:** `FITGRAPH=/Users/kelly/Developer/fitgraph python3 scripts/gen_kg_conformance_vectors.py`
Expected: existing lines + `wrote …workout_vectors.json: 3 workout vectors`. Confirm valid JSON.

- [ ] **Step 3: Write the failing test** `Tests/KGKitTests/WorkoutConformanceTests.swift`:
```swift
import XCTest
@testable import KGKit

final class WorkoutConformanceTests: XCTestCase {
    struct Vector: Decodable {
        struct MC: Decodable {
            let constraint_type: String, value: String, hard: Bool, negated: Bool
            let laterality: String?, graph_paths: [String], source_text: String
            let safety_behavior: String?, resolution_status: String
        }
        struct Rx: Decodable {
            let exercise_id: String, name: String
            let sets: Int?, reps: String?, rest_seconds: Int?, duration_seconds: Int?
        }
        struct Alt: Decodable { let filtered_exercise_id: String, alternative_exercise_id: String, score: Double }
        struct Expected: Decodable {
            let warmup: [Rx], main: [Rx], cooldown: [Rx]
            let selected_ids: [String], filtered_ids: [String], alternatives: [Alt]
        }
        let prompt: String, minutes: Int, available_equipment: [String]
        let member_constraints: [MC], expected: Expected
    }

    func testSwiftGeneratorMatchesOracle() throws {
        let a = try ArtifactLoader.bundled()
        let engine = SafetyEngine(graph: try LocalGraph(artifact: a), rules: a.safetyRules)
        let url = Bundle.module.url(forResource: "workout_vectors", withExtension: "json",
                                    subdirectory: "Fixtures/conformance")!
        let vectors = (try JSONDecoder().decode([String: [Vector]].self, from: Data(contentsOf: url)))["vectors"]!
        XCTAssertGreaterThan(vectors.count, 0)
        for v in vectors {
            let mc = v.member_constraints.map {
                ResolvedConstraint(constraintType: $0.constraint_type, value: $0.value, hard: $0.hard,
                                   sourceText: $0.source_text, graphPaths: $0.graph_paths,
                                   negated: $0.negated, laterality: $0.laterality,
                                   resolutionStatus: $0.resolution_status, safetyBehavior: $0.safety_behavior)
            }
            let plan = try WorkoutGenerator.generateWorkout(
                engine: engine, prompt: v.prompt, minutes: v.minutes,
                availableEquipment: v.available_equipment, memberConstraints: mc)
            let ctx = v.prompt
            func assertRx(_ got: [Prescription], _ exp: [Vector.Rx], _ which: String) {
                XCTAssertEqual(got.count, exp.count, "\(ctx)/\(which) count")
                for (g, e) in zip(got, exp) {
                    XCTAssertEqual(g.exerciseID, e.exercise_id, "\(ctx)/\(which) id")
                    XCTAssertEqual(g.sets, e.sets, "\(ctx)/\(which) sets")
                    XCTAssertEqual(g.reps, e.reps, "\(ctx)/\(which) reps")
                    XCTAssertEqual(g.restSeconds, e.rest_seconds, "\(ctx)/\(which) rest")
                    XCTAssertEqual(g.durationSeconds, e.duration_seconds, "\(ctx)/\(which) dur")
                }
            }
            assertRx(plan.warmup, v.expected.warmup, "warmup")
            assertRx(plan.main, v.expected.main, "main")
            assertRx(plan.cooldown, v.expected.cooldown, "cooldown")
            XCTAssertEqual(plan.selectedExercises.map { $0.exerciseID }, v.expected.selected_ids, "\(ctx)/selected")
            XCTAssertEqual(plan.filteredExercises.map { $0.exerciseID }, v.expected.filtered_ids, "\(ctx)/filtered")
            XCTAssertEqual(plan.alternatives.count, v.expected.alternatives.count, "\(ctx)/alt count")
            for (g, e) in zip(plan.alternatives, v.expected.alternatives) {
                XCTAssertEqual(g.filteredExerciseID, e.filtered_exercise_id, ctx)
                XCTAssertEqual(g.alternativeExerciseID, e.alternative_exercise_id, ctx)
                XCTAssertEqual(g.score, e.score, "\(ctx)/alt score")
            }
        }
    }
}
```
> The Python `_prescription` keys are `rest_seconds`/`duration_seconds`; the `Rx` Decodable maps them. If a JSON key is absent (e.g. a reps exercise has no `duration_seconds`), `Decodable` leaves the optional nil — which matches the Swift `Prescription` nil.

- [ ] **Step 4: Run, verify it passes:** `swift test --disable-sandbox --filter WorkoutConformanceTests`. Any divergence names the scenario/section — fix the Swift generator, never the vectors.

- [ ] **Step 5: README + full gate.** In `Sources/KGKit/README.md`, update the "What is NOT here yet" line to remove "Workout Generator" if listed (it isn't yet — leave member retrieval / 50-exercise scale-up / monorepo). Add a one-line note that the generator (surface A) is present. Then:
```bash
swift test --disable-sandbox --filter KGKitTests
swift test --disable-sandbox
git add scripts/gen_kg_conformance_vectors.py Tests/KGKitTests/Fixtures/conformance/workout_vectors.json Tests/KGKitTests/WorkoutConformanceTests.swift Sources/KGKit/README.md
git commit -m "feat(kgkit): workout-generator conformance vectors + README; surface A on-device"
```

## Self-review

- **Spec coverage:** types/helpers/sections = G1; composition/assembly = G2; oracle parity = G3. Member-graph derivation is deliberately out of scope (Codex lane); the generator consumes `availableEquipment` + `memberConstraints`.
- **No placeholders:** complete code throughout; only the generated `workout_vectors.json` comes from the committed generator command.
- **Type consistency:** `WorkoutPlan`/`Prescription`/`ExerciseSummary`/`AlternativeSummary` (G1) used by `generateWorkout` (G2) and the conformance test (G3). Reuses `Resolver.resolveText`, `SafetyEngine.evaluateCandidates`, `Alternatives.buildWorkoutCandidates`. `priorityScore`/`label`/`prescription`/`workoutSections`/`candidateIds`/`isLowerBodyCandidate` names consistent across tasks.
- **Determinism:** id-sorted candidates, `(-priority_score, id)` main sort, the mobility/main/cooldown slicing, and the prescription rules mirror the Python source; the G3 conformance gate re-verifies against the live oracle.
