# KGKit Resolver + Alternatives Swift Port — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the on-device Swift `KGKit` module with two more faithful ports of FitGraph's deterministic oracle — the **concept resolver** (`kg/resolver.py`: free text → typed `ResolvedConstraint`s) and **alternative selection** (`kg/alternatives.py`: safe-pool scoring → `AlternativeRecord`s) — proven byte-exact against the live Python oracle via new conformance vectors.

**Architecture:** Continues the [safety-core slice](2026-06-04-swift-kgkit-safety-core.md). The resolver is a faithful port of the exact/alias + hardcoded-canonical-case resolver (NO fuzzy/embedding — out of scope in the Python source by design) plus its multi-clause prompt splitter. Alternatives is a safe-pool scorer (Jaccard target overlap, pattern similarity, equipment preference, priority) with `round(weighted, 6)` + `(-score, id)` tie-break. The one parity-sensitive piece is the float `round(…,6)` — handled like the fingerprint, proven empirically via oracle-generated vectors. Everything loads the same frozen `kg_artifact.v0.json`.

**Tech Stack:** Swift 5.9 / SwiftPM, XCTest, Foundation. Python 3 + FitGraph (`/Users/kelly/Developer/fitgraph`) at vector-generation time only.

---

## Scope & non-goals

**In scope:** the Swift resolver (`resolveText` incl. multi-clause), the alternatives scorer/selector (`selectAlternatives` + `buildWorkoutCandidates`), the `ResolvedConstraint` field extension they require, and resolve/alternatives conformance harnesses.

**Out of scope (named follow-ons):** member-retrieval fact cards (Plan 3b), the 50-exercise canonical compiler (Plan 4), the app-local overlay workspace (Plan 5), monorepo migration (Plan 6). Fuzzy/embedding resolution is **not** in the Python source (brief 002 OOS) — not ported.

**Determinism invariants (preserve exactly):** sorted node iteration in `exactLabelOrAliasMatch`; the canonical-case branch order; the `(-score, id)` tie-break; `round(…,6)`; resolver/alternatives both pure graph traversal (no LLM/vector). Source-of-truth ports: `/Users/kelly/Developer/fitgraph/kg/resolver.py`, `kg/alternatives.py`, `kg/constraints.py`.

## File structure

| File | Responsibility |
|---|---|
| `Sources/KGKit/ResolvedConstraint.swift` (modify) | Add `graphPaths`, `verified`, `resolutionStatus`, `safetyBehavior` (defaults keep existing call sites compiling). |
| `Sources/KGKit/Resolver.swift` (create) | `normalize`, `exactLabelOrAliasMatch`, `resolveSingleClause` (canonical cases + `only …` subset), `resolvePromptClauses`, `resolveText`. |
| `Sources/KGKit/Alternatives.swift` (create) | `AlternativeRecord`, `WorkoutCandidateResult`, `roundTo6`, scoring helpers, `weightedScore`, `alternativePaths`, `selectAlternatives`, `buildWorkoutCandidates`. |
| `scripts/gen_kg_conformance_vectors.py` (modify) | Emit `resolve_vectors.json` + `alternatives_vectors.json` from the live oracle. |
| `Tests/KGKitTests/Fixtures/conformance/{resolve,alternatives}_vectors.json` (generated) | Golden vectors. |
| `Tests/KGKitTests/{ResolverTests,ResolveConformanceTests,AlternativesTests,AlternativesConformanceTests}.swift` | Unit + parity tests. |

---

### Task 1: Extend `ResolvedConstraint` to the full Python shape

**Files:** Modify `Sources/KGKit/ResolvedConstraint.swift`; Create `Tests/KGKitTests/ResolvedConstraintFieldsTests.swift`.

The Python `ResolvedConstraint` (`kg/constraints.py`) has `graph_paths`, `verified`, `resolution_status`, `safety_behavior` that the Swift struct lacks. Add them with defaults so existing safety-side call sites (which pass only the first six args) keep compiling.

- [ ] **Step 1: Write the failing test** `Tests/KGKitTests/ResolvedConstraintFieldsTests.swift`:
```swift
import XCTest
@testable import KGKit

final class ResolvedConstraintFieldsTests: XCTestCase {
    func testDefaultsMatchPythonDataclass() {
        let c = ResolvedConstraint(constraintType: "BodyRegion", value: "knee", hard: false, sourceText: "knee")
        XCTAssertEqual(c.graphPaths, [])
        XCTAssertFalse(c.verified)
        XCTAssertEqual(c.resolutionStatus, "resolved")
        XCTAssertNil(c.safetyBehavior)
    }
    func testRichConstruction() {
        let c = ResolvedConstraint(constraintType: "Equipment", value: "kettlebell", hard: true,
                                   sourceText: "only kettlebell", graphPaths: ["a -X-> b"],
                                   safetyBehavior: "allowed_equipment_only")
        XCTAssertEqual(c.graphPaths, ["a -X-> b"])
        XCTAssertEqual(c.safetyBehavior, "allowed_equipment_only")
        XCTAssertEqual(c.nodeID, "Equipment:kettlebell")
    }
    // Existing safety-side call shape must still compile unchanged:
    func testBackwardCompatibleInit() {
        let c = ResolvedConstraint(constraintType: "Equipment", value: "barbell", hard: true,
                                   sourceText: "no barbell", negated: true)
        XCTAssertTrue(c.negated)
        XCTAssertEqual(c.resolutionStatus, "resolved")
    }
}
```

- [ ] **Step 2: Run, verify it fails** (`extra argument 'graphPaths'`): `swift test --disable-sandbox --filter ResolvedConstraintFieldsTests`

- [ ] **Step 3: Replace `Sources/KGKit/ResolvedConstraint.swift` with:**
```swift
/// Mirror of kg/constraints.py ResolvedConstraint. Safety stays graph-driven;
/// this is parsed-input, not a decision.
public struct ResolvedConstraint: Equatable, Sendable {
    public let constraintType: String
    public let value: String
    public let hard: Bool
    public let sourceText: String
    public let graphPaths: [String]
    public let verified: Bool
    public let negated: Bool
    public let laterality: String?
    public let resolutionStatus: String
    public let safetyBehavior: String?

    public init(constraintType: String, value: String, hard: Bool, sourceText: String,
                graphPaths: [String] = [], verified: Bool = false,
                negated: Bool = false, laterality: String? = nil,
                resolutionStatus: String = "resolved", safetyBehavior: String? = nil) {
        self.constraintType = constraintType; self.value = value; self.hard = hard
        self.sourceText = sourceText; self.graphPaths = graphPaths; self.verified = verified
        self.negated = negated; self.laterality = laterality
        self.resolutionStatus = resolutionStatus; self.safetyBehavior = safetyBehavior
    }

    /// Node id this constraint refers to (_constraint_node_id in kg/safety.py).
    public var nodeID: String { NodeID.make(constraintType, value) }
}
```
(`NodeID` is unchanged — it lives in this file already; keep its existing definition below the struct.)

- [ ] **Step 4: Run, verify it passes** (3 tests) AND the existing suite still compiles: `swift test --disable-sandbox --filter ResolvedConstraintFieldsTests && swift test --disable-sandbox --filter KGKitTests`

- [ ] **Step 5: Commit**
```bash
git add Sources/KGKit/ResolvedConstraint.swift Tests/KGKitTests/ResolvedConstraintFieldsTests.swift
git commit -m "feat(kgkit): extend ResolvedConstraint to full Python shape (graphPaths/verified/resolutionStatus/safetyBehavior)"
```

---

### Task 2: Resolver core — normalize, exact/alias match, single-clause

**Files:** Create `Sources/KGKit/Resolver.swift`; Create `Tests/KGKitTests/ResolverTests.swift`.

Port `_normalize`, `_exact_label_or_alias_match`, `_resolved_node`, `_unresolved`, `_allowed_equipment_subset`, and `_resolve_single_clause` from `kg/resolver.py`. These throw because `_resolved_node` calls `graph.node(id)` (our `requireNode`).

- [ ] **Step 1: Write the failing test** `Tests/KGKitTests/ResolverTests.swift`:
```swift
import XCTest
@testable import KGKit

final class ResolverTests: XCTestCase {
    private func graph() throws -> LocalGraph {
        try LocalGraph(artifact: try ArtifactLoader.bundled())
    }

    func testNormalizeCollapsesAndStrips() {
        XCTAssertEqual(Resolver.normalize("  No   Barbell!! "), "no barbell")
        XCTAssertEqual(Resolver.normalize("(Kettlebell)"), "kettlebell")
    }

    func testNoBarbellNegatedEquipment() throws {
        let cs = try Resolver.resolveSingleClause("no barbell", graph: try graph())
        XCTAssertEqual(cs.count, 1)
        XCTAssertEqual(cs[0].constraintType, "Equipment")
        XCTAssertEqual(cs[0].value, "barbell")
        XCTAssertTrue(cs[0].hard); XCTAssertTrue(cs[0].negated)
    }

    func testExcludeDeadliftsFamily() throws {
        let cs = try Resolver.resolveSingleClause("exclude deadlifts", graph: try graph())
        XCTAssertEqual(cs[0].constraintType, "ExerciseFamily")
        XCTAssertEqual(cs[0].value, "deadlift_family")
        XCTAssertTrue(cs[0].negated)
    }

    func testLeftKneeHasLateralityAndPath() throws {
        let cs = try Resolver.resolveSingleClause("left knee", graph: try graph())
        XCTAssertEqual(cs[0].value, "left_knee")
        XCTAssertEqual(cs[0].laterality, "left")
        XCTAssertEqual(cs[0].graphPaths, ["BodyRegion:left_knee -PART_OF-> BodyRegion:knee"])
    }

    func testOnlyEquipmentSubset() throws {
        let cs = try Resolver.resolveSingleClause("only dumbbells and kettlebell", graph: try graph())
        XCTAssertEqual(cs.map { $0.constraintType }, ["Equipment", "Equipment"])
        XCTAssertEqual(Set(cs.map { $0.value }), ["dumbbell", "kettlebell"])
        XCTAssertTrue(cs.allSatisfy { $0.hard && $0.safetyBehavior == "allowed_equipment_only" })
    }

    func testUnknownTermIsUnresolvedHard() throws {
        let cs = try Resolver.resolveSingleClause("xyzzy", graph: try graph())
        XCTAssertEqual(cs[0].constraintType, "UnresolvedConcept")
        XCTAssertTrue(cs[0].hard)
        XCTAssertEqual(cs[0].resolutionStatus, "needs_review")
        XCTAssertEqual(cs[0].safetyBehavior, "ask_clarification")
    }
}
```
> Note: `testLeftKneeHasLateralityAndPath` and `testOnlyEquipmentSubset` assume the bundled seed contains `BodyRegion:left_knee -PART_OF-> BodyRegion:knee` and `Equipment` nodes whose aliases include `dumbbells`/`kettlebell`. The seed does (verified in the safety slice + resolver tests in fitgraph). If an assertion's exact value differs, the conformance harness (Task 4) is the authority — but these should hold as written.

- [ ] **Step 2: Run, verify it fails** (`cannot find 'Resolver' in scope`): `swift test --disable-sandbox --filter ResolverTests`

- [ ] **Step 3: Implement** `Sources/KGKit/Resolver.swift`:
```swift
import Foundation

/// Deterministic local resolver: free text -> typed constraints, never prose
/// decisions. Faithful port of kg/resolver.py (exact/alias + hardcoded canonical
/// cases + "only ..." subset; NO fuzzy/embedding — out of scope in the source).
public enum Resolver {
    private static let boundaryPunctuation = CharacterSet(charactersIn: ".,;:!?\"'()[]{}")

    /// Port of _normalize: trim, lowercase, collapse internal whitespace, strip boundary punctuation.
    public static func normalize(_ text: String) -> String {
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let collapsed = lowered.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return collapsed.trimmingCharacters(in: boundaryPunctuation)
    }

    private static func nodeValue(_ nodeID: String) -> String {
        String(nodeID.split(separator: ":", maxSplits: 1).last ?? "")
    }

    /// Port of _exact_label_or_alias_match: sorted by node id; match normalized label/aliases.
    static func exactLabelOrAliasMatch(_ normalized: String, _ graph: LocalGraph) -> GraphNode? {
        for node in graph.nodes.values.sorted(by: { $0.id < $1.id }) {
            var terms: Set<String> = [normalize(node.label)]
            for alias in node.aliases { terms.insert(normalize(alias)) }
            if terms.contains(normalized) { return node }
        }
        return nil
    }

    private static func resolvedNode(graph: LocalGraph, sourceText: String, constraintType: String,
                                     nodeID: String, hard: Bool = false, negated: Bool = false,
                                     laterality: String? = nil, safetyBehavior: String? = nil,
                                     graphPaths: [String] = []) throws -> ResolvedConstraint {
        _ = try graph.requireNode(nodeID)
        return ResolvedConstraint(constraintType: constraintType, value: nodeValue(nodeID), hard: hard,
                                  sourceText: sourceText, graphPaths: graphPaths, verified: false,
                                  negated: negated, laterality: laterality,
                                  resolutionStatus: "resolved", safetyBehavior: safetyBehavior)
    }

    private static func unresolved(sourceText: String, normalizedText: String) -> ResolvedConstraint {
        ResolvedConstraint(constraintType: "UnresolvedConcept", value: normalizedText, hard: true,
                           sourceText: sourceText, resolutionStatus: "needs_review",
                           safetyBehavior: "ask_clarification")
    }

    private static func splitEquipmentTerms(_ s: String) -> [String] {
        // Port of re.split(r"\s*(?:,| and )\s*", ...): split on comma or " and ".
        let sentinel = "\u{1}"
        let replaced = s.replacingOccurrences(of: "\\s*(?:,| and )\\s*", with: sentinel, options: .regularExpression)
        return replaced.split(separator: Character(sentinel), omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Port of _allowed_equipment_subset: "only X, Y and Z" -> hard Equipment constraints; nil if any non-equipment.
    private static func allowedEquipmentSubset(text: String, normalized: String,
                                               graph: LocalGraph) throws -> [ResolvedConstraint]? {
        guard normalized.hasPrefix("only ") else { return nil }
        let equipmentText = String(normalized.dropFirst("only ".count)).trimmingCharacters(in: .whitespaces)
        let terms = splitEquipmentTerms(equipmentText)
        if terms.isEmpty { return nil }
        var constraints: [ResolvedConstraint] = []
        var seen: Set<String> = []
        for term in terms {
            guard let node = exactLabelOrAliasMatch(term, graph), node.type == "Equipment" else { return nil }
            if seen.contains(node.id) { continue }
            seen.insert(node.id)
            constraints.append(try resolvedNode(graph: graph, sourceText: text, constraintType: "Equipment",
                                                 nodeID: node.id, hard: true,
                                                 safetyBehavior: "allowed_equipment_only"))
        }
        return constraints
    }

    /// Port of _resolve_single_clause.
    public static func resolveSingleClause(_ text: String, graph: LocalGraph) throws -> [ResolvedConstraint] {
        let normalized = normalize(text)
        if let eq = try allowedEquipmentSubset(text: text, normalized: normalized, graph: graph) { return eq }

        switch normalized {
        case "knee":
            return [try resolvedNode(graph: graph, sourceText: text, constraintType: "BodyRegion",
                                     nodeID: "BodyRegion:knee",
                                     graphPaths: try graph.partOfClosurePaths("BodyRegion:knee"))]
        case "left knee":
            let paths = graph.outgoing("BodyRegion:left_knee", predicate: "PART_OF").map { $0.path() }
            return [try resolvedNode(graph: graph, sourceText: text, constraintType: "BodyRegion",
                                     nodeID: "BodyRegion:left_knee", laterality: "left", graphPaths: paths)]
        case "bad lower back":
            return [try resolvedNode(graph: graph, sourceText: text, constraintType: "BodyRegion",
                                     nodeID: "BodyRegion:lower_back", hard: true,
                                     safetyBehavior: "block_if_safety_critical",
                                     graphPaths: try graph.partOfClosurePaths("BodyRegion:lower_back"))]
        case "kettlebell":
            return [try resolvedNode(graph: graph, sourceText: text, constraintType: "Equipment",
                                     nodeID: "Equipment:kettlebell")]
        case "no barbell":
            return [try resolvedNode(graph: graph, sourceText: text, constraintType: "Equipment",
                                     nodeID: "Equipment:barbell", hard: true, negated: true)]
        case "exclude deadlifts":
            return [try resolvedNode(graph: graph, sourceText: text, constraintType: "ExerciseFamily",
                                     nodeID: "ExerciseFamily:deadlift_family", hard: true, negated: true)]
        default:
            if let node = exactLabelOrAliasMatch(normalized, graph) {
                return [try resolvedNode(graph: graph, sourceText: text, constraintType: node.type, nodeID: node.id)]
            }
            return [unresolved(sourceText: text, normalizedText: normalized)]
        }
    }
}
```

- [ ] **Step 4: Run, verify it passes** (6 tests): `swift test --disable-sandbox --filter ResolverTests`

- [ ] **Step 5: Commit**
```bash
git add Sources/KGKit/Resolver.swift Tests/KGKitTests/ResolverTests.swift
git commit -m "feat(kgkit): resolver core — normalize, exact/alias match, single-clause canonical cases"
```

---

### Task 3: Resolver multi-clause prompts + `resolveText`

**Files:** Modify `Sources/KGKit/Resolver.swift` (add to the enum); Create `Tests/KGKitTests/ResolverMultiClauseTests.swift`.

Port `_prompt_clauses`, `_is_request_shape_clause`, `_resolve_prompt_clauses`, and the public `resolve_text`.

- [ ] **Step 1: Write the failing test** `Tests/KGKitTests/ResolverMultiClauseTests.swift`:
```swift
import XCTest
@testable import KGKit

final class ResolverMultiClauseTests: XCTestCase {
    private func graph() throws -> LocalGraph { try LocalGraph(artifact: try ArtifactLoader.bundled()) }

    func testSingleClauseShortCircuits() throws {
        let cs = try Resolver.resolveText("no barbell", graph: try graph())
        XCTAssertEqual(cs.count, 1)
        XCTAssertEqual(cs[0].value, "barbell")
    }

    func testMultiClauseSkipsRequestShapeAndResolvesRest() throws {
        let cs = try Resolver.resolveText("Build a session. No barbell. Exclude deadlifts.", graph: try graph())
        // "Build a session" is request-shape (skipped); the other two resolve.
        let values = Set(cs.map { $0.value })
        XCTAssertTrue(values.contains("barbell"))
        XCTAssertTrue(values.contains("deadlift_family"))
        XCTAssertFalse(cs.contains { $0.constraintType == "UnresolvedConcept" })
    }

    func testAllUnresolvedMultiClauseReturnsUnresolved() throws {
        let cs = try Resolver.resolveText("Frobnicate the wibble. Glorp the snarf.", graph: try graph())
        XCTAssertTrue(cs.allSatisfy { $0.constraintType == "UnresolvedConcept" })
    }
}
```

- [ ] **Step 2: Run, verify it fails** (`has no member 'resolveText'`): `swift test --disable-sandbox --filter ResolverMultiClauseTests`

- [ ] **Step 3: Add to the `Resolver` enum** (in `Sources/KGKit/Resolver.swift`):
```swift
    private static let requestVerbs = ["build ", "create ", "make ", "plan ", "program "]
    private static let requestNouns = ["session", "workout", "routine", "plan"]

    /// Port of _prompt_clauses: split on . ; ! ? keeping the delimiter; keep clauses that normalize non-empty.
    private static func promptClauses(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "[^.;!?]+[.;!?]*")
        let ns = text as NSString
        var out: [String] = []
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let clause = ns.substring(with: m.range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalize(clause).isEmpty { out.append(clause) }
        }
        return out
    }

    private static func isRequestShapeClause(_ normalized: String) -> Bool {
        requestVerbs.contains { normalized.hasPrefix($0) } && requestNouns.contains { normalized.contains($0) }
    }

    /// Port of _resolve_prompt_clauses.
    private static func resolvePromptClauses(_ text: String, graph: LocalGraph) throws -> [ResolvedConstraint]? {
        let clauses = promptClauses(text)
        if clauses.count <= 1 { return nil }
        var resolved: [ResolvedConstraint] = []
        var unresolved: [ResolvedConstraint] = []
        for clause in clauses {
            if isRequestShapeClause(normalize(clause)) { continue }
            let cs = try resolveSingleClause(clause, graph: graph)
            if cs.count == 1 && cs[0].constraintType == "UnresolvedConcept" {
                unresolved.append(contentsOf: cs)
            } else {
                resolved.append(contentsOf: cs)
            }
        }
        if !resolved.isEmpty { return resolved + unresolved }
        if !unresolved.isEmpty { return unresolved }
        return nil
    }

    /// Port of resolve_text: single-clause first; fall back to multi-clause only if the single result is one UnresolvedConcept.
    public static func resolveText(_ text: String, graph: LocalGraph) throws -> [ResolvedConstraint] {
        let single = try resolveSingleClause(text, graph: graph)
        if !(single.count == 1 && single[0].constraintType == "UnresolvedConcept") { return single }
        if let prompt = try resolvePromptClauses(text, graph: graph) { return prompt }
        return single
    }
```

- [ ] **Step 4: Run, verify it passes** (3 tests): `swift test --disable-sandbox --filter ResolverMultiClauseTests`

- [ ] **Step 5: Commit**
```bash
git add Sources/KGKit/Resolver.swift Tests/KGKitTests/ResolverMultiClauseTests.swift
git commit -m "feat(kgkit): resolver multi-clause prompt splitting + resolveText"
```

---

### Task 4: Resolve conformance vectors (parity vs the Python oracle)

**Files:** Modify `scripts/gen_kg_conformance_vectors.py`; generate `Tests/KGKitTests/Fixtures/conformance/resolve_vectors.json`; Create `Tests/KGKitTests/ResolveConformanceTests.swift`.

- [ ] **Step 1: Extend the generator.** Append to `scripts/gen_kg_conformance_vectors.py` before `if __name__`:
```python
from kg.resolver import resolve_text  # noqa: E402

RESOLVE_VECTORS = REPO / "Tests/KGKitTests/Fixtures/conformance/resolve_vectors.json"

RESOLVE_PROMPTS = [
    "knee", "left knee", "bad lower back", "kettlebell", "no barbell",
    "exclude deadlifts", "only dumbbells and kettlebell", "squat", "xyzzy",
    "Build a session. No barbell. Exclude deadlifts.",
    "Frobnicate the wibble. Glorp the snarf.",
]


def emit_resolve_vectors() -> None:
    graph = load_local_graph(FITGRAPH / "graph" / "exercise_kg.seed.json")
    vectors = []
    for prompt in RESOLVE_PROMPTS:
        constraints = resolve_text(prompt, graph)
        vectors.append({
            "text": prompt,
            "expected": [
                {"constraint_type": c.constraint_type, "value": c.value, "hard": c.hard,
                 "negated": c.negated, "laterality": c.laterality, "graph_paths": list(c.graph_paths),
                 "verified": c.verified, "resolution_status": c.resolution_status,
                 "safety_behavior": c.safety_behavior}
                for c in constraints
            ],
        })
    RESOLVE_VECTORS.parent.mkdir(parents=True, exist_ok=True)
    RESOLVE_VECTORS.write_text(json.dumps({"vectors": vectors}, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {RESOLVE_VECTORS.relative_to(REPO)}: {len(vectors)} resolve vectors")
```
And update `if __name__ == "__main__":` to also call `emit_resolve_vectors()` (keep `freeze_artifact()` and `emit_vectors()`).

- [ ] **Step 2: Generate:** `FITGRAPH=/Users/kelly/Developer/fitgraph python3 scripts/gen_kg_conformance_vectors.py`
Expected: a `wrote …resolve_vectors.json: 11 resolve vectors` line. Confirm valid JSON.

- [ ] **Step 3: Write the failing test** `Tests/KGKitTests/ResolveConformanceTests.swift`:
```swift
import XCTest
@testable import KGKit

final class ResolveConformanceTests: XCTestCase {
    struct Vector: Decodable {
        struct Constraint: Decodable {
            let constraint_type: String, value: String, hard: Bool, negated: Bool
            let laterality: String?, graph_paths: [String], verified: Bool
            let resolution_status: String, safety_behavior: String?
        }
        let text: String; let expected: [Constraint]
    }

    func testSwiftResolverMatchesOracle() throws {
        let graph = try LocalGraph(artifact: try ArtifactLoader.bundled())
        let url = Bundle.module.url(forResource: "resolve_vectors", withExtension: "json",
                                    subdirectory: "Fixtures/conformance")!
        let vectors = (try JSONDecoder().decode([String: [Vector]].self, from: Data(contentsOf: url)))["vectors"]!
        XCTAssertGreaterThan(vectors.count, 0)
        for v in vectors {
            let got = try Resolver.resolveText(v.text, graph: graph)
            XCTAssertEqual(got.count, v.expected.count, v.text)
            for (g, e) in zip(got, v.expected) {
                XCTAssertEqual(g.constraintType, e.constraint_type, v.text)
                XCTAssertEqual(g.value, e.value, v.text)
                XCTAssertEqual(g.hard, e.hard, v.text)
                XCTAssertEqual(g.negated, e.negated, v.text)
                XCTAssertEqual(g.laterality, e.laterality, v.text)
                XCTAssertEqual(g.graphPaths, e.graph_paths, v.text)
                XCTAssertEqual(g.resolutionStatus, e.resolution_status, v.text)
                XCTAssertEqual(g.safetyBehavior, e.safety_behavior, v.text)
            }
        }
    }
}
```

- [ ] **Step 4: Run, verify it passes:** `swift test --disable-sandbox --filter ResolveConformanceTests`. If a vector diverges, the message names the prompt — fix the Swift resolver to match the oracle, never edit the vectors.

- [ ] **Step 5: Commit**
```bash
git add scripts/gen_kg_conformance_vectors.py Tests/KGKitTests/Fixtures/conformance/resolve_vectors.json Tests/KGKitTests/ResolveConformanceTests.swift
git commit -m "feat(kgkit): resolve conformance vectors proving oracle parity"
```

---

### Task 5: Alternatives — types, scoring, `weightedScore`

**Files:** Create `Sources/KGKit/Alternatives.swift`; Create `Tests/KGKitTests/AlternativesScoringTests.swift`.

Port the records + scoring from `kg/alternatives.py`. `roundTo6` must match Python `round(x, 6)` (round-half-to-even).

- [ ] **Step 1: Write the failing test** `Tests/KGKitTests/AlternativesScoringTests.swift`:
```swift
import XCTest
@testable import KGKit

final class AlternativesScoringTests: XCTestCase {
    func testRoundTo6() {
        XCTAssertEqual(Alternatives.roundTo6(0.1 + 0.2), 0.3)
        XCTAssertEqual(Alternatives.roundTo6(0.45 * (1.0/3.0)), 0.15)
        XCTAssertEqual(Alternatives.roundTo6(0.12345678), 0.123457) // rounds up at the 7th decimal (not a tie)
    }

    func testWeightedScoreComposesWeights() {
        let s = Alternatives.weightedScore([
            "target_overlap": 1.0, "movement_pattern_similarity": 1.0,
            "equipment_preference": 1.0, "priority_tier": 0.5,
        ])
        XCTAssertEqual(s, Alternatives.roundTo6(0.45 + 0.35 + 0.10 + 0.05))
        XCTAssertEqual(s, 0.95)
    }
}
```
> If `testRoundTo6`'s `0.1234565 -> 0.123456` half-to-even case proves platform-fragile, the Task 7 conformance gate (real oracle values) is the authority; keep the first two assertions which are exact.

- [ ] **Step 2: Run, verify it fails** (`cannot find 'Alternatives' in scope`): `swift test --disable-sandbox --filter AlternativesScoringTests`

- [ ] **Step 3: Implement** `Sources/KGKit/Alternatives.swift`:
```swift
import Foundation

/// One deterministic alternative for a filtered exercise (kg/alternatives.py AlternativeRecord).
public struct AlternativeRecord: Equatable, Sendable {
    public let filteredExerciseID: String
    public let alternativeExerciseID: String
    public let derivedFrom: String
    public let score: Double
    public let scoreComponents: [String: Double]
    public let graphPaths: [String]
}

/// Small workout-candidate contract (kg/alternatives.py WorkoutCandidateResult).
public struct WorkoutCandidateResult: Equatable, Sendable {
    public let selectedReceipts: [DecisionReceipt]
    public let filteredReceipts: [DecisionReceipt]
    public let alternatives: [AlternativeRecord]
}

/// Port of kg/alternatives.py. Alternatives come only from the already-safe (selected) pool.
public enum Alternatives {
    /// Python round(x, 6), round-half-to-even.
    public static func roundTo6(_ x: Double) -> Double {
        (x * 1_000_000).rounded(.toNearestOrEven) / 1_000_000
    }

    private static func targets(_ g: LocalGraph, _ id: String) -> Set<String> {
        Set(g.outgoing(id, predicate: "TARGETS").map { $0.target })
    }
    private static func patterns(_ g: LocalGraph, _ id: String) -> Set<String> {
        Set(g.outgoing(id, predicate: "HAS_PATTERN").map { $0.target })
    }
    private static func requires(_ g: LocalGraph, _ id: String) -> Set<String> {
        Set(g.outgoing(id, predicate: "REQUIRES").map { $0.target })
    }
    private static func priorityScore(_ g: LocalGraph, _ id: String) -> Double {
        if let node = g.nodes[id], case let .double(v)? = node.properties["priority_score"] { return v }
        return 0.0
    }

    private static func targetOverlap(_ g: LocalGraph, _ filtered: String, _ alt: String) -> Double {
        let a = targets(g, filtered), b = targets(g, alt)
        if a.isEmpty || b.isEmpty { return 0.0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }
    private static func patternSimilarity(_ g: LocalGraph, _ filtered: String, _ alt: String) -> Double {
        let a = patterns(g, filtered), b = patterns(g, alt)
        if a.isEmpty || b.isEmpty { return 0.0 }
        return a.isDisjoint(with: b) ? 0.0 : 1.0
    }
    private static func equipmentPreference(_ g: LocalGraph, _ alt: String, _ available: Set<String>) -> Double {
        let req = requires(g, alt)
        if req.isEmpty { return 1.0 }
        return req.isSubset(of: available) ? 1.0 : 0.0
    }

    static func scoreComponents(_ g: LocalGraph, _ filtered: String, _ alt: String,
                                _ available: Set<String>) -> [String: Double] {
        [
            "target_overlap": targetOverlap(g, filtered, alt),
            "movement_pattern_similarity": patternSimilarity(g, filtered, alt),
            "equipment_preference": equipmentPreference(g, alt, available),
            "priority_tier": priorityScore(g, alt),
        ]
    }

    /// Port of _weighted_score.
    public static func weightedScore(_ c: [String: Double]) -> Double {
        roundTo6(
            0.45 * (c["target_overlap"] ?? 0)
          + 0.35 * (c["movement_pattern_similarity"] ?? 0)
          + 0.10 * (c["equipment_preference"] ?? 0)
          + 0.10 * (c["priority_tier"] ?? 0)
        )
    }

    /// Port of _equipment_ids (same normalization as the safety engine).
    static func equipmentIDs(_ available: [String]) -> Set<String> {
        Set(available.map { NodeID.make("Equipment", $0) })
    }
}
```

- [ ] **Step 4: Run, verify it passes** (2 tests): `swift test --disable-sandbox --filter AlternativesScoringTests`

- [ ] **Step 5: Commit**
```bash
git add Sources/KGKit/Alternatives.swift Tests/KGKitTests/AlternativesScoringTests.swift
git commit -m "feat(kgkit): alternatives types + scoring (round-to-6, weighted components)"
```

---

### Task 6: Alternatives — paths + selection

**Files:** Modify `Sources/KGKit/Alternatives.swift` (add to the enum); Create `Tests/KGKitTests/AlternativesSelectTests.swift`.

Port `_alternative_paths`, `select_alternatives`, `build_workout_candidates`.

- [ ] **Step 1: Write the failing test** `Tests/KGKitTests/AlternativesSelectTests.swift`:
```swift
import XCTest
@testable import KGKit

final class AlternativesSelectTests: XCTestCase {
    private func engineAndGraph() throws -> (SafetyEngine, LocalGraph) {
        let artifact = try ArtifactLoader.bundled()
        let g = try LocalGraph(artifact: artifact)
        return (SafetyEngine(graph: g, rules: artifact.safetyRules), g)
    }

    func testSelectsOneAlternativePerFilteredFromSafePool() throws {
        let (engine, g) = try engineAndGraph()
        // Jordan-style scenario: left-knee restriction filters at least one exercise.
        let knee = ResolvedConstraint(constraintType: "BodyRegion", value: "left_knee",
                                      hard: true, sourceText: "left knee")
        let receipts = try engine.evaluateCandidates(availableEquipment: ["Dumbbell", "Kettlebell", "Yoga Mat"],
                                                     constraints: [knee])
        let result = try Alternatives.buildWorkoutCandidates(receipts,
                            availableEquipment: ["Dumbbell", "Kettlebell", "Yoga Mat"], graph: g)
        // One alternative per filtered receipt; each alternative is from the selected pool.
        XCTAssertEqual(result.alternatives.count, result.filteredReceipts.count)
        let selectedIDs = Set(result.selectedReceipts.map { $0.exerciseID })
        for alt in result.alternatives {
            XCTAssertTrue(selectedIDs.contains(alt.alternativeExerciseID), alt.alternativeExerciseID)
            XCTAssertEqual(alt.derivedFrom, alt.filteredExerciseID)
        }
    }

    func testNoSafePoolYieldsNoAlternatives() throws {
        let (_, g) = try engineAndGraph()
        // No "selected" receipts -> no pool to draw from (returns before touching the graph).
        let filteredOnly = [DecisionReceipt(
            exerciseID: "Exercise:x", decision: "filtered", primarySeverity: "MEDICAL_HARD_BLOCK",
            reasonCodes: ["R"], primaryReasonCode: "R", graphPaths: [], constraintFingerprint: "f",
            graphVersion: "v", rulesetVersion: "v", ontologyLockVersion: "v")]
        let alts = try Alternatives.selectAlternatives(filteredOnly, availableEquipment: [], graph: g)
        XCTAssertEqual(alts.count, 0)
    }
}
```

- [ ] **Step 2: Run, verify it fails** (`has no member 'buildWorkoutCandidates'`): `swift test --disable-sandbox --filter AlternativesSelectTests`

- [ ] **Step 3: Add to the `Alternatives` enum:**
```swift
    /// Port of _alternative_paths.
    static func alternativePaths(_ g: LocalGraph, _ filtered: String, _ alt: String) -> [String] {
        var paths: [String] = []
        let sharedTargets = targets(g, filtered).intersection(targets(g, alt))
        let sharedPatterns = patterns(g, filtered).intersection(patterns(g, alt))
        for e in g.outgoing(filtered, predicate: "TARGETS") where sharedTargets.contains(e.target) { paths.append(e.path()) }
        for e in g.outgoing(alt, predicate: "TARGETS") where sharedTargets.contains(e.target) { paths.append(e.path()) }
        for e in g.outgoing(filtered, predicate: "HAS_PATTERN") where sharedPatterns.contains(e.target) { paths.append(e.path()) }
        for e in g.outgoing(alt, predicate: "HAS_PATTERN") where sharedPatterns.contains(e.target) { paths.append(e.path()) }
        for predicate in ["REQUIRES", "STRESSES"] {
            paths.append(contentsOf: g.outgoing(alt, predicate: predicate).map { $0.path() })
        }
        return paths
    }

    /// Port of select_alternatives: one best alternative per filtered receipt, drawn only from selected receipts.
    public static func selectAlternatives(_ receipts: [DecisionReceipt], availableEquipment: [String],
                                          graph: LocalGraph) throws -> [AlternativeRecord] {
        let safeIDs = receipts.filter { $0.decision == "selected" }.map { $0.exerciseID }
        if safeIDs.isEmpty { return [] }
        let available = equipmentIDs(availableEquipment)
        let sortedSafe = safeIDs.sorted()
        let filtered = receipts.filter { $0.decision == "filtered" }.sorted { $0.exerciseID < $1.exerciseID }
        var out: [AlternativeRecord] = []
        for f in filtered {
            var scored: [AlternativeRecord] = []
            for altID in sortedSafe {
                let comps = scoreComponents(graph, f.exerciseID, altID, available)
                scored.append(AlternativeRecord(
                    filteredExerciseID: f.exerciseID, alternativeExerciseID: altID, derivedFrom: f.exerciseID,
                    score: weightedScore(comps), scoreComponents: comps,
                    graphPaths: alternativePaths(graph, f.exerciseID, altID)))
            }
            scored.sort { a, b in
                if a.score != b.score { return a.score > b.score }          // higher score first
                return a.alternativeExerciseID < b.alternativeExerciseID     // tie -> smaller id (Python (-score, id))
            }
            out.append(scored[0])
        }
        return out
    }

    /// Port of build_workout_candidates.
    public static func buildWorkoutCandidates(_ receipts: [DecisionReceipt], availableEquipment: [String],
                                              graph: LocalGraph) throws -> WorkoutCandidateResult {
        WorkoutCandidateResult(
            selectedReceipts: receipts.filter { $0.decision == "selected" },
            filteredReceipts: receipts.filter { $0.decision == "filtered" },
            alternatives: try selectAlternatives(receipts, availableEquipment: availableEquipment, graph: graph))
    }
```
> Tie-break note: Python sorts by `(-score, id)` ascending — i.e. higher score first, then lexicographically smaller id. The Swift `scored.sort { ($0.score, $1.alternativeExerciseID) > ($1.score, $0.alternativeExerciseID) }` reproduces this: higher score wins; on equal score the **smaller** id wins (because the id comparands are swapped). Verify against the conformance gate (Task 7).

- [ ] **Step 4: Run, verify it passes** (2 tests): `swift test --disable-sandbox --filter AlternativesSelectTests`

- [ ] **Step 5: Commit**
```bash
git add Sources/KGKit/Alternatives.swift Tests/KGKitTests/AlternativesSelectTests.swift
git commit -m "feat(kgkit): alternative paths + safe-pool selection with (-score,id) tie-break"
```

---

### Task 7: Alternatives conformance vectors + README + full-suite gate

**Files:** Modify `scripts/gen_kg_conformance_vectors.py`; generate `Tests/KGKitTests/Fixtures/conformance/alternatives_vectors.json`; Create `Tests/KGKitTests/AlternativesConformanceTests.swift`; Modify `Sources/KGKit/README.md`.

- [ ] **Step 1: Extend the generator.** Append before `if __name__`:
```python
from kg.alternatives import select_alternatives  # noqa: E402

ALT_VECTORS = REPO / "Tests/KGKitTests/Fixtures/conformance/alternatives_vectors.json"


def emit_alternatives_vectors() -> None:
    graph = load_local_graph(FITGRAPH / "graph" / "exercise_kg.seed.json")
    rules = load_safety_rules(FITGRAPH / "graph")
    jordan_equipment = ["Dumbbell", "Kettlebell", "Yoga Mat"]
    constraints = (_c(constraint_type="BodyRegion", value="left_knee", hard=True, source_text="left knee"),)
    receipts = evaluate_candidates(available_equipment=jordan_equipment,
                                   constraints=constraints, graph=graph, safety_rules=rules)
    alts = select_alternatives(receipts, available_equipment=jordan_equipment, graph=graph)
    vector = {
        "available_equipment": jordan_equipment,
        "constraints": [{"constraint_type": c.constraint_type, "value": c.value, "hard": c.hard,
                         "source_text": c.source_text, "negated": c.negated} for c in constraints],
        "expected_alternatives": [
            {"filtered_exercise_id": a.filtered_exercise_id,
             "alternative_exercise_id": a.alternative_exercise_id, "derived_from": a.derived_from,
             "score": a.score, "score_components": a.score_components, "graph_paths": list(a.graph_paths)}
            for a in alts
        ],
    }
    ALT_VECTORS.parent.mkdir(parents=True, exist_ok=True)
    ALT_VECTORS.write_text(json.dumps({"vectors": [vector]}, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {ALT_VECTORS.relative_to(REPO)}: {len(vector['expected_alternatives'])} alternatives")
```
Update `if __name__ == "__main__":` to also call `emit_alternatives_vectors()`.

- [ ] **Step 2: Generate** all vectors: `FITGRAPH=/Users/kelly/Developer/fitgraph python3 scripts/gen_kg_conformance_vectors.py`
Expected: lines for the artifact, safety vectors, resolve vectors, and `alternatives_vectors.json`.

- [ ] **Step 3: Write the failing test** `Tests/KGKitTests/AlternativesConformanceTests.swift`:
```swift
import XCTest
@testable import KGKit

final class AlternativesConformanceTests: XCTestCase {
    struct Vector: Decodable {
        struct C: Decodable { let constraint_type: String, value: String, hard: Bool, source_text: String, negated: Bool }
        struct Alt: Decodable {
            let filtered_exercise_id: String, alternative_exercise_id: String, derived_from: String
            let score: Double, score_components: [String: Double], graph_paths: [String]
        }
        let available_equipment: [String]; let constraints: [C]; let expected_alternatives: [Alt]
    }

    func testSwiftAlternativesMatchOracle() throws {
        let artifact = try ArtifactLoader.bundled()
        let g = try LocalGraph(artifact: artifact)
        let engine = SafetyEngine(graph: g, rules: artifact.safetyRules)
        let url = Bundle.module.url(forResource: "alternatives_vectors", withExtension: "json",
                                    subdirectory: "Fixtures/conformance")!
        let vectors = (try JSONDecoder().decode([String: [Vector]].self, from: Data(contentsOf: url)))["vectors"]!
        for v in vectors {
            let constraints = v.constraints.map {
                ResolvedConstraint(constraintType: $0.constraint_type, value: $0.value, hard: $0.hard,
                                   sourceText: $0.source_text, negated: $0.negated)
            }
            let receipts = try engine.evaluateCandidates(availableEquipment: v.available_equipment, constraints: constraints)
            let got = try Alternatives.selectAlternatives(receipts, availableEquipment: v.available_equipment, graph: g)
            XCTAssertEqual(got.count, v.expected_alternatives.count)
            for (a, e) in zip(got, v.expected_alternatives) {
                XCTAssertEqual(a.filteredExerciseID, e.filtered_exercise_id)
                XCTAssertEqual(a.alternativeExerciseID, e.alternative_exercise_id, "selected alt for \(e.filtered_exercise_id)")
                XCTAssertEqual(a.derivedFrom, e.derived_from)
                XCTAssertEqual(a.score, e.score, "score for \(e.filtered_exercise_id) -> \(e.alternative_exercise_id)")
                XCTAssertEqual(a.graphPaths, e.graph_paths)
                for (k, ev) in e.score_components { XCTAssertEqual(a.scoreComponents[k], ev, k) }
            }
        }
    }
}
```

- [ ] **Step 4: Run, verify it passes:** `swift test --disable-sandbox --filter AlternativesConformanceTests`. If `score` fails by a tiny float delta, the `roundTo6` port diverges from Python `round(…,6)` — fix the rounding, do not loosen the assertion or edit the vector.

- [ ] **Step 5: Update the README + run the full gate.** Replace the "What is NOT here yet" line in `Sources/KGKit/README.md` to drop "Resolver, alternatives" (now present) and keep "member retrieval, 50-exercise scale-up, monorepo package integration." Then:
```bash
swift test --disable-sandbox --filter KGKitTests   # whole KGKit suite green
swift test --disable-sandbox                       # whole package, no regressions
git add scripts/gen_kg_conformance_vectors.py Tests/KGKitTests/Fixtures/conformance/alternatives_vectors.json Tests/KGKitTests/AlternativesConformanceTests.swift Sources/KGKit/README.md
git commit -m "feat(kgkit): alternatives conformance vectors + README; resolver+alternatives parity complete"
```

---

## Self-review

- **Spec coverage:** resolver (`normalize`/exact-alias/canonical cases/`only …`/multi-clause/`resolveText`) = Tasks 2–3; resolver parity = Task 4; alternatives (records/scoring/`round(,6)`/paths/selection/tie-break) = Tasks 5–6; alternatives parity = Task 7. The `ResolvedConstraint` extension they depend on = Task 1. Member retrieval and the 50-exercise compiler are explicitly out of scope.
- **No placeholders:** every code step is complete. The only generated artifacts are the two `*_vectors.json` (produced by the committed generator command).
- **Type consistency:** `ResolvedConstraint` (Task 1) → `Resolver` (2–3) returns `[ResolvedConstraint]`; `Alternatives` (5–6) consumes `[DecisionReceipt]` (from the existing `SafetyEngine.evaluateCandidates`) and the graph's `TARGETS`/`HAS_PATTERN`/`REQUIRES` edges + `priority_score`. `equipmentIDs`/`NodeID.make` reused from the safety slice. `roundTo6`/`weightedScore`/`selectAlternatives` names are consistent across Tasks 5–7.
- **Determinism:** sorted node iteration in `exactLabelOrAliasMatch`, canonical-branch order, sorted safe pool + sorted filtered receipts, and the `(-score, id)` tie-break mirror the Python source; the conformance gates (Tasks 4, 7) re-verify everything against the live oracle.
