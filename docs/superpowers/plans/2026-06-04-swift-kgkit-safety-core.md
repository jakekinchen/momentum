# Swift kgkit — Deterministic Safety Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up an on-device, fully-offline Swift `CamiFitKG` module that runs FitGraph's deterministic safety-by-traversal (medical + equipment + prompt-exclusion blocks, the severity lattice, decision receipts) and produces receipts that are **byte-identical** to FitGraph's Python oracle, proven by a golden conformance-vector harness.

**Architecture:** This is the first executable slice of the synthesis plan's Phase 1 ([docs/design/2026-06-04-camifit-fitgraph-synthesis.md](../../design/2026-06-04-camifit-fitgraph-synthesis.md) §4–§6). A small Python generator (the embryo of the future canonical compiler) reads FitGraph's seed graph + safety rules, freezes a Swift-loadable **graph artifact** JSON, and runs the live Python oracle over a set of scenarios to emit **golden conformance vectors**. The Swift `CamiFitKG` runtime loads the same frozen artifact and must reproduce every receipt — `decision`, `primary_severity`, ordered `reason_codes`, `graph_paths`, and the `sha256[:16]` `constraint_fingerprint` — exactly. A failing parity assertion fails the build. The deterministic levers from the Python source (sorted traversals, BFS `PART_OF` paths, sorted-key compact-JSON fingerprint) are ported verbatim.

**Tech Stack:** Swift 5.9 / SwiftPM (existing `Package.swift`), XCTest, CryptoKit (`SHA256`), Foundation `Codable`. Python 3 + the existing FitGraph `kg/` package (`/Users/kelly/Developer/fitgraph`) for vector generation only — Python never ships at runtime.

---

## Scope, non-goals, and sequence

**In scope (this plan):** the Swift safety core only — graph model, artifact loader, `PART_OF` traversal, the three reason generators (`_medical_reasons`, `_equipment_reasons`, `_prompt_exclusion_reasons`), the severity lattice, receipt assembly, the canonical-JSON fingerprint, and the conformance-vector parity harness.

**Out of scope (named follow-on plans):**
- *Plan 2 — Resolver port:* `resolve_text` (normalize + exact/alias + canonical cases + `only …` subset + `UnresolvedConcept`) and the on-device fuzzy pass.
- *Plan 3 — Alternatives + member retrieval:* `select_alternatives` scoring and the copilot fact cards.
- *Plan 4 — Canonical compiler + 50-exercise scale-up:* grow the artifact from the golden `data/exercises.json`, precomputed closures, exact-count CI gate.
- *Plan 5 — Monorepo migration:* fold FitGraph in as `kg-canonical/`, dual-loop isolation.

This plan deliberately constructs `ResolvedConstraint` values directly in tests/generators (mirroring FitGraph's `tests/test_safety.py`), so it does **not** depend on the resolver. It produces working, testable software on its own: `swift test` proves on-device safety parity.

**Determinism invariants to preserve (from FitGraph, non-negotiable):** deterministic graph traversal decides safety (no LLM, no vector search); sorted node/edge iteration; BFS `PART_OF` path with edges sorted by target; fingerprint over sorted-key compact JSON. Source of truth ports: `/Users/kelly/Developer/fitgraph/kg/safety.py`, `kg/graph_store.py`, `kg/provenance.py`, `kg/constraints.py`, `graph/safety_rules.seed.json`, `graph/exercise_kg.seed.json`.

## File structure

| File | Responsibility |
|---|---|
| `Package.swift` (modify) | Add `CamiFitKG` library target (+ bundled `Resources/Artifact`) and `CamiFitKGTests` test target (+ `Fixtures`). |
| `Sources/CamiFitKG/GraphModel.swift` | `GraphNode`, `GraphEdge` (with `path()`), value types. |
| `Sources/CamiFitKG/GraphArtifact.swift` | `Codable` frozen artifact (`nodes`, `edges`, `safetyRules`, version stamps) + load from `Data`/`Bundle`. |
| `Sources/CamiFitKG/LocalGraph.swift` | Closed-world snapshot: `node`, `outgoing`, `incoming`, `nodesByType`, `partOfPath`, `partOfClosurePaths`. |
| `Sources/CamiFitKG/ResolvedConstraint.swift` | Typed constraint struct (mirror of `kg/constraints.py`). |
| `Sources/CamiFitKG/SafetyRule.swift` | `SafetyRule` value type + property-match helper. |
| `Sources/CamiFitKG/CanonicalJSON.swift` | Python-`json.dumps`-compatible serializer + `sha256[:16]` fingerprint. |
| `Sources/CamiFitKG/DecisionReceipt.swift` | Receipt struct + `severityRank`/`primarySeverity` lattice. |
| `Sources/CamiFitKG/SafetyEngine.swift` | The three reason generators + receipt assembly + `evaluateCandidates`. |
| `Sources/CamiFitKG/Resources/Artifact/kg_artifact.v0.json` | Frozen graph artifact (generated from FitGraph seed). |
| `scripts/gen_kg_conformance_vectors.py` | Generator: freezes the artifact + emits golden vectors from the live oracle. |
| `Tests/CamiFitKGTests/Fixtures/conformance/safety_vectors.json` | Golden vectors (generated, committed). |
| `Tests/CamiFitKGTests/*.swift` | Unit tests + `ConformanceTests`. |

---

### Task 1: Add the `CamiFitKG` module + test target

**Files:**
- Modify: `Package.swift`
- Create: `Sources/CamiFitKG/Version.swift`
- Create: `Tests/CamiFitKGTests/ModuleSmokeTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CamiFitKGTests/ModuleSmokeTests.swift`:

```swift
import XCTest
@testable import CamiFitKG

final class ModuleSmokeTests: XCTestCase {
    func testModuleVersionStampsArePresent() {
        XCTAssertEqual(CamiFitKG.graphVersion, "fitgraph-kg-m5-validation-v0")
        XCTAssertEqual(CamiFitKG.rulesetVersion, "ruleset-m2-safety-v0")
        XCTAssertEqual(CamiFitKG.ontologyLockVersion, "ontology-lock-m0-unverified")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --disable-sandbox --filter CamiFitKGTests`
Expected: FAIL — `no such module 'CamiFitKG'` (target does not exist yet).

- [ ] **Step 3: Add the targets and the version constants**

In `Package.swift`, add to `products`:

```swift
        .library(
            name: "CamiFitKG",
            targets: ["CamiFitKG"]
        ),
```

In `Package.swift`, add to `targets` (place after the `CamiFitEngine` target):

```swift
        .target(
            name: "CamiFitKG",
            resources: [
                .copy("Resources/Artifact")
            ]
        ),
        .testTarget(
            name: "CamiFitKGTests",
            dependencies: ["CamiFitKG"],
            resources: [
                .copy("Fixtures")
            ]
        ),
```

Create `Sources/CamiFitKG/Version.swift`:

```swift
/// On-device FitGraph KG runtime. Version stamps are frozen by the build-time
/// canonical layer and carried in every DecisionReceipt for provenance.
/// Mirrors GRAPH_VERSION / RULESET_VERSION (kg/validation.py) and
/// ONTOLOGY_LOCK_VERSION (kg/safety.py).
public enum CamiFitKG {
    public static let graphVersion = "fitgraph-kg-m5-validation-v0"
    public static let rulesetVersion = "ruleset-m2-safety-v0"
    public static let ontologyLockVersion = "ontology-lock-m0-unverified"
}
```

Create a placeholder so the resource directory exists: `Sources/CamiFitKG/Resources/Artifact/.gitkeep` (empty file). (Task 6 replaces this with the real artifact; `.copy` requires the directory to exist now.)

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --disable-sandbox --filter CamiFitKGTests`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/CamiFitKG/Version.swift Sources/CamiFitKG/Resources/Artifact/.gitkeep Tests/CamiFitKGTests/ModuleSmokeTests.swift
git commit -m "feat(kgkit): add CamiFitKG module + version stamps"
```

---

### Task 2: Graph model value types

**Files:**
- Create: `Sources/CamiFitKG/GraphModel.swift`
- Create: `Tests/CamiFitKGTests/GraphModelTests.swift`

Port `GraphNode` / `GraphEdge` from `kg/graph_store.py`. `GraphEdge.path()` is the exact evidence-string format used in every receipt.

- [ ] **Step 1: Write the failing test**

Create `Tests/CamiFitKGTests/GraphModelTests.swift`:

```swift
import XCTest
@testable import CamiFitKG

final class GraphModelTests: XCTestCase {
    func testEdgePathFormatMatchesPythonEvidenceString() {
        let edge = GraphEdge(source: "BodyRegion:left_knee", predicate: "PART_OF", target: "BodyRegion:knee", properties: [:])
        XCTAssertEqual(edge.path(), "BodyRegion:left_knee -PART_OF-> BodyRegion:knee")
    }

    func testNodeKeepsAliasesAndProperties() {
        let node = GraphNode(id: "Equipment:kettlebell", type: "Equipment", label: "Kettlebell",
                             aliases: ["kettlebell", "kb"], properties: [:])
        XCTAssertEqual(node.type, "Equipment")
        XCTAssertEqual(node.aliases, ["kettlebell", "kb"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --disable-sandbox --filter GraphModelTests`
Expected: FAIL — `cannot find 'GraphEdge' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/CamiFitKG/GraphModel.swift`:

```swift
/// Property values in the seed graph are JSON scalars (string/bool/number).
/// A small closed enum keeps edge property matching deterministic and Codable.
public enum PropertyValue: Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case double(Double)
    case null
}

public struct GraphNode: Equatable, Sendable {
    public let id: String
    public let type: String
    public let label: String
    public let aliases: [String]
    public let properties: [String: PropertyValue]

    public init(id: String, type: String, label: String,
                aliases: [String] = [], properties: [String: PropertyValue] = [:]) {
        self.id = id; self.type = type; self.label = label
        self.aliases = aliases; self.properties = properties
    }
}

public struct GraphEdge: Equatable, Sendable {
    public let source: String
    public let predicate: String
    public let target: String
    public let properties: [String: PropertyValue]

    public init(source: String, predicate: String, target: String,
                properties: [String: PropertyValue] = [:]) {
        self.source = source; self.predicate = predicate
        self.target = target; self.properties = properties
    }

    /// Exact port of GraphEdge.path() (kg/graph_store.py): the receipt evidence string.
    public func path() -> String { "\(source) -\(predicate)-> \(target)" }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --disable-sandbox --filter GraphModelTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CamiFitKG/GraphModel.swift Tests/CamiFitKGTests/GraphModelTests.swift
git commit -m "feat(kgkit): graph node/edge value types with path() evidence string"
```

---

### Task 3: `Codable` graph artifact + decode

**Files:**
- Create: `Sources/CamiFitKG/SafetyRule.swift`
- Create: `Sources/CamiFitKG/GraphArtifact.swift`
- Create: `Tests/CamiFitKGTests/GraphArtifactDecodeTests.swift`

The artifact is the frozen JSON the Swift runtime loads. `PropertyValue` and the rule `match.properties` decode from heterogeneous JSON (string, bool, or array-of-strings), so a custom decoder is required.

- [ ] **Step 1: Write the failing test**

Create `Tests/CamiFitKGTests/GraphArtifactDecodeTests.swift`:

```swift
import XCTest
@testable import CamiFitKG

final class GraphArtifactDecodeTests: XCTestCase {
    static let json = """
    {
      "graph_version": "fitgraph-kg-m5-validation-v0",
      "ruleset_version": "ruleset-m2-safety-v0",
      "ontology_lock_version": "ontology-lock-m0-unverified",
      "nodes": [
        {"id": "BodyRegion:knee", "type": "BodyRegion", "label": "knee", "aliases": ["knee"], "properties": {"laterality": "neutral"}},
        {"id": "BodyRegion:left_knee", "type": "BodyRegion", "label": "left knee", "aliases": ["left knee"], "properties": {"laterality": "left"}},
        {"id": "Exercise:goblet_squat", "type": "Exercise", "label": "Goblet Squat", "aliases": [], "properties": {"priority_score": 0.7}}
      ],
      "edges": [
        {"source": "BodyRegion:left_knee", "predicate": "PART_OF", "target": "BodyRegion:knee", "properties": {"runtime_safety_edge": true}},
        {"source": "Exercise:goblet_squat", "predicate": "STRESSES", "target": "BodyRegion:left_knee", "properties": {"loaded": true, "flexion_depth": "deep", "load_level": "high"}}
      ],
      "safety_rules": [
        {"id": "SafetyRule:avoid_loaded_knee_flexion", "severity": "MEDICAL_HARD_BLOCK", "reason_code": "ACTIVE_KNEE_RESTRICTION", "uses_concepts": ["BodyRegion:knee"], "match": {"edge_predicate": "STRESSES", "properties": {"loaded": true, "flexion_depth": ["deep"], "load_level": ["medium", "high"]}}}
      ]
    }
    """

    func testDecodesNodesEdgesAndRules() throws {
        let artifact = try GraphArtifact.decode(from: Data(Self.json.utf8))
        XCTAssertEqual(artifact.graphVersion, "fitgraph-kg-m5-validation-v0")
        XCTAssertEqual(artifact.nodes.count, 3)
        XCTAssertEqual(artifact.edges.count, 2)
        XCTAssertEqual(artifact.safetyRules.count, 1)
        let stress = artifact.edges.first { $0.predicate == "STRESSES" }!
        XCTAssertEqual(stress.properties["loaded"], .bool(true))
        XCTAssertEqual(stress.properties["flexion_depth"], .string("deep"))
        let rule = artifact.safetyRules[0]
        XCTAssertEqual(rule.reasonCode, "ACTIVE_KNEE_RESTRICTION")
        XCTAssertEqual(rule.usesConcepts, ["BodyRegion:knee"])
        XCTAssertEqual(rule.matchEdgePredicate, "STRESSES")
        XCTAssertEqual(rule.matchProperties["flexion_depth"], .anyOf(["deep"]))
        XCTAssertEqual(rule.matchProperties["loaded"], .exact(.bool(true)))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --disable-sandbox --filter GraphArtifactDecodeTests`
Expected: FAIL — `cannot find 'GraphArtifact' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/CamiFitKG/SafetyRule.swift`:

```swift
/// A rule property matcher mirrors kg/safety.py `_matches_properties`:
/// a list expectation means "actual must be one of these"; a scalar means "equal".
public enum RuleMatch: Equatable, Sendable {
    case exact(PropertyValue)
    case anyOf([PropertyValue])

    /// Port of `_matches_properties` semantics for a single property.
    func matches(_ actual: PropertyValue?) -> Bool {
        switch self {
        case .exact(let expected): return actual == expected
        case .anyOf(let options): return actual.map { options.contains($0) } ?? false
        }
    }
}

public struct SafetyRule: Equatable, Sendable {
    public let id: String
    public let severity: String
    public let reasonCode: String
    public let usesConcepts: [String]
    public let matchEdgePredicate: String?
    public let matchProperties: [String: RuleMatch]
}
```

Create `Sources/CamiFitKG/GraphArtifact.swift`:

```swift
import Foundation

public struct GraphArtifact: Sendable {
    public let graphVersion: String
    public let rulesetVersion: String
    public let ontologyLockVersion: String
    public let nodes: [GraphNode]
    public let edges: [GraphEdge]
    public let safetyRules: [SafetyRule]

    public enum DecodeError: Error, Equatable { case malformed(String) }

    public static func decode(from data: Data) throws -> GraphArtifact {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodeError.malformed("root is not an object")
        }
        func str(_ k: String) throws -> String {
            guard let v = root[k] as? String else { throw DecodeError.malformed("missing string \(k)") }
            return v
        }
        let nodes = try (root["nodes"] as? [[String: Any]] ?? []).map(decodeNode)
        let edges = try (root["edges"] as? [[String: Any]] ?? []).map(decodeEdge)
        let rules = try (root["safety_rules"] as? [[String: Any]] ?? []).map(decodeRule)
        return GraphArtifact(
            graphVersion: try str("graph_version"),
            rulesetVersion: try str("ruleset_version"),
            ontologyLockVersion: try str("ontology_lock_version"),
            nodes: nodes, edges: edges, safetyRules: rules
        )
    }

    private static func decodeProps(_ raw: Any?) -> [String: PropertyValue] {
        guard let dict = raw as? [String: Any] else { return [:] }
        var out: [String: PropertyValue] = [:]
        for (k, v) in dict { out[k] = scalar(v) }
        return out
    }

    private static func scalar(_ v: Any) -> PropertyValue {
        if let num = v as? NSNumber {
            // Distinguish JSON booleans from numbers: JSONSerialization encodes
            // true/false as a CFBoolean-backed NSNumber, which would otherwise
            // mis-cast to .double and break rule matching on `loaded: true`.
            if CFGetTypeID(num) == CFBooleanGetTypeID() { return .bool(num.boolValue) }
            return .double(num.doubleValue)
        }
        if let s = v as? String { return .string(s) }
        return .null
    }

    private static func decodeNode(_ d: [String: Any]) throws -> GraphNode {
        guard let id = d["id"] as? String, let type = d["type"] as? String,
              let label = d["label"] as? String else {
            throw DecodeError.malformed("node missing id/type/label")
        }
        return GraphNode(id: id, type: type, label: label,
                         aliases: (d["aliases"] as? [String]) ?? [],
                         properties: decodeProps(d["properties"]))
    }

    private static func decodeEdge(_ d: [String: Any]) throws -> GraphEdge {
        guard let s = d["source"] as? String, let p = d["predicate"] as? String,
              let t = d["target"] as? String else {
            throw DecodeError.malformed("edge missing source/predicate/target")
        }
        return GraphEdge(source: s, predicate: p, target: t, properties: decodeProps(d["properties"]))
    }

    private static func decodeRule(_ d: [String: Any]) throws -> SafetyRule {
        guard let id = d["id"] as? String, let sev = d["severity"] as? String,
              let rc = d["reason_code"] as? String else {
            throw DecodeError.malformed("rule missing id/severity/reason_code")
        }
        let match = d["match"] as? [String: Any] ?? [:]
        var matchProps: [String: RuleMatch] = [:]
        for (k, v) in (match["properties"] as? [String: Any] ?? [:]) {
            if let arr = v as? [Any] {
                matchProps[k] = .anyOf(arr.map(scalar))
            } else {
                matchProps[k] = .exact(scalar(v))
            }
        }
        return SafetyRule(
            id: id, severity: sev, reasonCode: rc,
            usesConcepts: (d["uses_concepts"] as? [String]) ?? [],
            matchEdgePredicate: match["edge_predicate"] as? String,
            matchProperties: matchProps
        )
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --disable-sandbox --filter GraphArtifactDecodeTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CamiFitKG/SafetyRule.swift Sources/CamiFitKG/GraphArtifact.swift Tests/CamiFitKGTests/GraphArtifactDecodeTests.swift
git commit -m "feat(kgkit): Codable graph artifact + safety-rule match decoding"
```

---

### Task 4: `LocalGraph` traversal (`outgoing`/`incoming`/`nodesByType`)

**Files:**
- Create: `Sources/CamiFitKG/LocalGraph.swift`
- Create: `Tests/CamiFitKGTests/LocalGraphTests.swift`

Port the closed-world snapshot from `kg/graph_store.py` (`LocalGraph`), including the load-time validation (duplicate ids, dangling edge endpoints).

- [ ] **Step 1: Write the failing test**

Create `Tests/CamiFitKGTests/LocalGraphTests.swift`:

```swift
import XCTest
@testable import CamiFitKG

final class LocalGraphTests: XCTestCase {
    private func graph() throws -> LocalGraph {
        let artifact = try GraphArtifact.decode(from: Data(GraphArtifactDecodeTests.json.utf8))
        return try LocalGraph(artifact: artifact)
    }

    func testOutgoingFiltersByPredicate() throws {
        let g = try graph()
        let stresses = g.outgoing("Exercise:goblet_squat", predicate: "STRESSES")
        XCTAssertEqual(stresses.map { $0.target }, ["BodyRegion:left_knee"])
        XCTAssertEqual(g.outgoing("Exercise:goblet_squat", predicate: "REQUIRES").count, 0)
    }

    func testNodesByTypeAndUnknownNodeThrows() throws {
        let g = try graph()
        XCTAssertEqual(g.nodesByType("Exercise").map { $0.id }, ["Exercise:goblet_squat"])
        XCTAssertThrowsError(try g.requireNode("Exercise:nope"))
    }

    func testDuplicateNodeIDsRejected() {
        let dup = """
        {"graph_version":"v","ruleset_version":"v","ontology_lock_version":"v",
         "nodes":[{"id":"A","type":"X","label":"a"},{"id":"A","type":"X","label":"a"}],
         "edges":[],"safety_rules":[]}
        """
        XCTAssertThrowsError(try LocalGraph(artifact: try GraphArtifact.decode(from: Data(dup.utf8))))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --disable-sandbox --filter LocalGraphTests`
Expected: FAIL — `cannot find 'LocalGraph' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/CamiFitKG/LocalGraph.swift`:

```swift
public struct LocalGraph: Sendable {
    public let nodes: [String: GraphNode]
    public let edges: [GraphEdge]

    public enum GraphError: Error, Equatable {
        case duplicateNodeID(String)
        case danglingEdge(String)
        case unknownNode(String)
    }

    /// Port of load_local_graph validation: unique ids, closed-world edge endpoints.
    public init(artifact: GraphArtifact) throws {
        var byID: [String: GraphNode] = [:]
        for node in artifact.nodes {
            if byID[node.id] != nil { throw GraphError.duplicateNodeID(node.id) }
            byID[node.id] = node
        }
        for edge in artifact.edges {
            if byID[edge.source] == nil { throw GraphError.danglingEdge(edge.source) }
            if byID[edge.target] == nil { throw GraphError.danglingEdge(edge.target) }
        }
        self.nodes = byID
        self.edges = artifact.edges
    }

    @discardableResult
    public func requireNode(_ id: String) throws -> GraphNode {
        guard let node = nodes[id] else { throw GraphError.unknownNode(id) }
        return node
    }

    public func outgoing(_ id: String, predicate: String? = nil) -> [GraphEdge] {
        edges.filter { $0.source == id && (predicate == nil || $0.predicate == predicate) }
    }

    public func incoming(_ id: String, predicate: String? = nil) -> [GraphEdge] {
        edges.filter { $0.target == id && (predicate == nil || $0.predicate == predicate) }
    }

    public func nodesByType(_ type: String) -> [GraphNode] {
        // Deterministic: sort by id (Python sorts candidate exercises by id).
        nodes.values.filter { $0.type == type }.sorted { $0.id < $1.id }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --disable-sandbox --filter LocalGraphTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CamiFitKG/LocalGraph.swift Tests/CamiFitKGTests/LocalGraphTests.swift
git commit -m "feat(kgkit): LocalGraph closed-world snapshot + traversal"
```

---

### Task 5: `PART_OF` BFS path + closure paths

**Files:**
- Modify: `Sources/CamiFitKG/LocalGraph.swift`
- Create: `Tests/CamiFitKGTests/PartOfTraversalTests.swift`

Port `part_of_path` (BFS, outgoing `PART_OF` edges **sorted by target**, return first path) and `part_of_closure_paths` (DFS over incoming `PART_OF`, edges **sorted by source**) verbatim — these produce the exact `graph_paths` evidence strings.

- [ ] **Step 1: Write the failing test**

Create `Tests/CamiFitKGTests/PartOfTraversalTests.swift`:

```swift
import XCTest
@testable import CamiFitKG

final class PartOfTraversalTests: XCTestCase {
    private func graph() throws -> LocalGraph {
        try LocalGraph(artifact: try GraphArtifact.decode(from: Data(GraphArtifactDecodeTests.json.utf8)))
    }

    func testPartOfPathLeftKneeToKnee() throws {
        let g = try graph()
        XCTAssertEqual(try g.partOfPath(from: "BodyRegion:left_knee", to: "BodyRegion:knee"),
                       ["BodyRegion:left_knee -PART_OF-> BodyRegion:knee"])
    }

    func testPartOfPathSameNodeIsEmpty() throws {
        let g = try graph()
        XCTAssertEqual(try g.partOfPath(from: "BodyRegion:knee", to: "BodyRegion:knee"), [])
    }

    func testPartOfPathNoConnectionIsEmpty() throws {
        let g = try graph()
        XCTAssertEqual(try g.partOfPath(from: "BodyRegion:knee", to: "BodyRegion:left_knee"), [])
    }

    func testClosurePathsFromKnee() throws {
        let g = try graph()
        XCTAssertEqual(try g.partOfClosurePaths("BodyRegion:knee"),
                       ["BodyRegion:left_knee -PART_OF-> BodyRegion:knee"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --disable-sandbox --filter PartOfTraversalTests`
Expected: FAIL — `value of type 'LocalGraph' has no member 'partOfPath'`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/CamiFitKG/LocalGraph.swift` (inside the `LocalGraph` struct):

```swift
    /// Port of part_of_path: one deterministic PART_OF path source->target (BFS,
    /// outgoing edges sorted by target). Empty if source==target or no path.
    public func partOfPath(from source: String, to target: String) throws -> [String] {
        try requireNode(source); try requireNode(target)
        if source == target { return [] }
        var queue: [(String, [String])] = [(source, [])]
        var seen: Set<String> = [source]
        while !queue.isEmpty {
            let (current, path) = queue.removeFirst()
            for edge in outgoing(current, predicate: "PART_OF").sorted(by: { $0.target < $1.target }) {
                let next = path + [edge.path()]
                if edge.target == target { return next }
                if !seen.contains(edge.target) {
                    seen.insert(edge.target)
                    queue.append((edge.target, next))
                }
            }
        }
        return []
    }

    /// Port of part_of_closure_paths: paths proving PART_OF descendants of root
    /// (DFS over incoming PART_OF, edges sorted by source).
    public func partOfClosurePaths(_ root: String) throws -> [String] {
        try requireNode(root)
        var paths: [String] = []
        var seen: Set<String> = [root]
        var stack: [String] = [root]
        while let current = stack.popLast() {
            for edge in incoming(current, predicate: "PART_OF").sorted(by: { $0.source < $1.source }) {
                if !seen.contains(edge.source) {
                    seen.insert(edge.source)
                    paths.append(edge.path())
                    stack.append(edge.source)
                }
            }
        }
        return paths
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --disable-sandbox --filter PartOfTraversalTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CamiFitKG/LocalGraph.swift Tests/CamiFitKGTests/PartOfTraversalTests.swift
git commit -m "feat(kgkit): PART_OF BFS path + closure-path traversal"
```

---

### Task 6: `ResolvedConstraint` + node-id normalization + the frozen artifact

**Files:**
- Create: `Sources/CamiFitKG/ResolvedConstraint.swift`
- Create: `scripts/gen_kg_conformance_vectors.py`
- Create (generated): `Sources/CamiFitKG/Resources/Artifact/kg_artifact.v0.json`
- Create: `Tests/CamiFitKGTests/NodeIDTests.swift`

`ResolvedConstraint` mirrors `kg/constraints.py`. `nodeID(prefix:value:)` ports `_node_id` (`kg/safety.py`). The generator script freezes FitGraph's seed into the Swift artifact (and, in Task 12, emits vectors).

- [ ] **Step 1: Write the failing test**

Create `Tests/CamiFitKGTests/NodeIDTests.swift`:

```swift
import XCTest
@testable import CamiFitKG

final class NodeIDTests: XCTestCase {
    func testNodeIDNormalization() {
        XCTAssertEqual(NodeID.make("Equipment", "Kettlebell"), "Equipment:kettlebell")
        XCTAssertEqual(NodeID.make("BodyRegion", "left knee"), "BodyRegion:left_knee")
        XCTAssertEqual(NodeID.make("Equipment", "Equipment:barbell"), "Equipment:barbell") // already-prefixed passthrough
    }

    func testConstraintDefaults() {
        let c = ResolvedConstraint(constraintType: "BodyRegion", value: "left_knee", hard: true, sourceText: "left knee")
        XCTAssertFalse(c.negated)
        XCTAssertNil(c.laterality)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --disable-sandbox --filter NodeIDTests`
Expected: FAIL — `cannot find 'NodeID' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/CamiFitKG/ResolvedConstraint.swift`:

```swift
/// Mirror of kg/constraints.py ResolvedConstraint. Safety stays graph-driven;
/// this is parsed-input, not a decision.
public struct ResolvedConstraint: Equatable, Sendable {
    public let constraintType: String
    public let value: String
    public let hard: Bool
    public let sourceText: String
    public let negated: Bool
    public let laterality: String?

    public init(constraintType: String, value: String, hard: Bool, sourceText: String,
                negated: Bool = false, laterality: String? = nil) {
        self.constraintType = constraintType; self.value = value; self.hard = hard
        self.sourceText = sourceText; self.negated = negated; self.laterality = laterality
    }

    /// Node id this constraint refers to (_constraint_node_id in kg/safety.py).
    public var nodeID: String { NodeID.make(constraintType, value) }
}

/// Port of _node_id (kg/safety.py): "Prefix:value" with value lowercased,
/// spaces -> underscores, trimmed; already-prefixed values pass through.
public enum NodeID {
    public static func make(_ prefix: String, _ value: String) -> String {
        if value.hasPrefix("\(prefix):") { return value }
        let normalized = value.trimmingCharacters(in: .whitespaces)
            .lowercased().replacingOccurrences(of: " ", with: "_")
        return "\(prefix):\(normalized)"
    }
}
```

Create `scripts/gen_kg_conformance_vectors.py` (artifact freeze first; vector emission added in Task 12):

```python
#!/usr/bin/env python3
"""Freeze the FitGraph seed graph into the Swift kgkit artifact, and (Task 12)
emit golden conformance vectors from the live Python oracle.

Run from the camifit repo root:
    FITGRAPH=/Users/kelly/Developer/fitgraph python3 scripts/gen_kg_conformance_vectors.py
"""
import json, os, sys
from pathlib import Path

FITGRAPH = Path(os.environ.get("FITGRAPH", "/Users/kelly/Developer/fitgraph"))
sys.path.insert(0, str(FITGRAPH))

from kg.graph_store import load_local_graph  # noqa: E402
from kg.safety import load_safety_rules, ONTOLOGY_LOCK_VERSION  # noqa: E402
from kg.validation import GRAPH_VERSION, RULESET_VERSION  # noqa: E402

REPO = Path(__file__).resolve().parents[1]
ARTIFACT = REPO / "Sources/CamiFitKG/Resources/Artifact/kg_artifact.v0.json"


def freeze_artifact() -> None:
    graph = load_local_graph(FITGRAPH / "graph" / "exercise_kg.seed.json")
    rules = load_safety_rules(FITGRAPH / "graph")
    artifact = {
        "graph_version": GRAPH_VERSION,
        "ruleset_version": RULESET_VERSION,
        "ontology_lock_version": ONTOLOGY_LOCK_VERSION,
        "nodes": [
            {"id": n.id, "type": n.type, "label": n.label,
             "aliases": list(n.aliases), "properties": n.properties or {}}
            for n in sorted(graph.nodes.values(), key=lambda x: x.id)
        ],
        "edges": [
            {"source": e.source, "predicate": e.predicate, "target": e.target,
             "properties": e.properties or {}}
            for e in graph.edges
        ],
        "safety_rules": [
            {"id": r.id, "severity": r.severity, "reason_code": r.reason_code,
             "uses_concepts": list(r.uses_concepts), "match": r.match}
            for r in rules
        ],
    }
    ARTIFACT.parent.mkdir(parents=True, exist_ok=True)
    ARTIFACT.write_text(json.dumps(artifact, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {ARTIFACT.relative_to(REPO)}: "
          f"{len(artifact['nodes'])} nodes / {len(artifact['edges'])} edges / "
          f"{len(artifact['safety_rules'])} rules")


if __name__ == "__main__":
    freeze_artifact()
```

Generate the artifact (the `.gitkeep` may stay alongside it — harmless):

```bash
FITGRAPH=/Users/kelly/Developer/fitgraph python3 scripts/gen_kg_conformance_vectors.py
```

Expected stdout: `wrote Sources/CamiFitKG/Resources/Artifact/kg_artifact.v0.json: 25 nodes / 28 edges / 3 rules` (counts reflect the current FitGraph seed; if they differ, that is fine — the artifact is whatever the seed contains).

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --disable-sandbox --filter NodeIDTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CamiFitKG/ResolvedConstraint.swift scripts/gen_kg_conformance_vectors.py Sources/CamiFitKG/Resources/Artifact/kg_artifact.v0.json Tests/CamiFitKGTests/NodeIDTests.swift
git commit -m "feat(kgkit): ResolvedConstraint, node-id normalization, frozen graph artifact"
```

---

### Task 7: Canonical-JSON fingerprint (byte-exact `stable_fingerprint` parity)

**Files:**
- Create: `Sources/CamiFitKG/CanonicalJSON.swift`
- Create: `Tests/CamiFitKGTests/CanonicalFingerprintTests.swift`

This is the load-bearing parity primitive (synthesis doc §4.4 / R2). It must reproduce `json.dumps(payload, sort_keys=True, separators=(",",":"))` exactly — including `ensure_ascii` (non-ASCII → `\uXXXX`), unescaped `/`, and `true`/`false` — then `sha256(...).hexdigest()[:16]`. The expected values below are produced by Python and pinned.

> **Generate the golden expectations once (paste real values into the test):**
> ```bash
> python3 - <<'PY'
> import json, hashlib
> def fp(p): return hashlib.sha256(json.dumps(p, sort_keys=True, separators=(",",":")).encode()).hexdigest()[:16]
> ascii_payload = {"available_equipment":["Equipment:dumbbell","Equipment:kettlebell"],
>   "constraints":[{"constraint_type":"BodyRegion","value":"left_knee","hard":True,"negated":False,"source_text":"left knee"}],
>   "exercise_id":"Exercise:goblet_squat"}
> print("ASCII canonical:", json.dumps(ascii_payload, sort_keys=True, separators=(",",":")))
> print("ASCII fp:", fp(ascii_payload))
> uni = {"available_equipment":[], "constraints":[], "exercise_id":"Exercise:café/squat"}
> print("UNICODE canonical:", json.dumps(uni, sort_keys=True, separators=(",",":")))
> print("UNICODE fp:", fp(uni))
> PY
> ```

- [ ] **Step 1: Write the failing test** (replace the two `EXPECTED_*` placeholders with the printed values)

Create `Tests/CamiFitKGTests/CanonicalFingerprintTests.swift`:

```swift
import XCTest
@testable import CamiFitKG

final class CanonicalFingerprintTests: XCTestCase {
    func testAsciiCanonicalStringAndFingerprint() {
        let c = ResolvedConstraint(constraintType: "BodyRegion", value: "left_knee", hard: true,
                                   sourceText: "left knee", negated: false)
        let canonical = CanonicalJSON.fingerprintPayload(
            availableEquipment: ["Equipment:dumbbell", "Equipment:kettlebell"],
            constraints: [c], exerciseID: "Exercise:goblet_squat")
        XCTAssertEqual(canonical,
          #"{"available_equipment":["Equipment:dumbbell","Equipment:kettlebell"],"constraints":[{"constraint_type":"BodyRegion","hard":true,"negated":false,"source_text":"left knee","value":"left_knee"}],"exercise_id":"Exercise:goblet_squat"}"#)
        XCTAssertEqual(CanonicalJSON.sha256Prefix16(canonical), "EXPECTED_ASCII_FP")
    }

    func testEnsureAsciiAndUnescapedSlash() {
        // Non-ASCII -> \uXXXX (ensure_ascii); '/' stays unescaped. Mirrors Python json.dumps.
        let canonical = CanonicalJSON.fingerprintPayload(
            availableEquipment: [], constraints: [], exerciseID: "Exercise:café/squat")
        // ensure_ascii: output must contain no raw non-ASCII scalar, and '/' must
        // NOT be escaped. Asserted structurally + via the Python-pinned fingerprint,
        // so this file needs no hand-typed \uXXXX escape sequence.
        XCTAssertFalse(canonical.unicodeScalars.contains { $0.value > 0x7F },
                       "ensure_ascii: output must contain no raw non-ASCII scalars")
        XCTAssertTrue(canonical.contains("/"), "'/' must appear")
        XCTAssertFalse(canonical.contains("\\/"), "'/' must NOT be escaped")
        XCTAssertEqual(CanonicalJSON.sha256Prefix16(canonical), "EXPECTED_UNICODE_FP")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --disable-sandbox --filter CanonicalFingerprintTests`
Expected: FAIL — `cannot find 'CanonicalJSON' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/CamiFitKG/CanonicalJSON.swift`:

```swift
import Foundation
import CryptoKit

/// Reproduces Python json.dumps(sort_keys=True, separators=(",",":"), ensure_ascii=True)
/// for the fixed fingerprint payload, then sha256(...)[:16]. This guarantees the Swift
/// DecisionReceipt.constraint_fingerprint matches FitGraph's stable_fingerprint byte-for-byte.
public enum CanonicalJSON {
    /// JSON string escaping identical to Python's ensure_ascii encoder:
    /// escape " \ and the named control chars; other controls and all non-ASCII -> \uXXXX
    /// (astral chars become surrogate pairs); '/' is NOT escaped.
    public static func encodeString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{09}": out += "\\t"
            case "\u{0A}": out += "\\n"
            case "\u{0C}": out += "\\f"
            case "\u{0D}": out += "\\r"
            default:
                let v = scalar.value
                if v < 0x20 {
                    out += String(format: "\\u%04x", v)
                } else if v < 0x80 {
                    out.unicodeScalars.append(scalar)
                } else if v > 0xFFFF {
                    let u = v - 0x10000
                    out += String(format: "\\u%04x\\u%04x", 0xD800 + (u >> 10), 0xDC00 + (u & 0x3FF))
                } else {
                    out += String(format: "\\u%04x", v)
                }
            }
        }
        return out + "\""
    }

    /// Build the canonical fingerprint payload string. Top-level keys
    /// (available_equipment, constraints, exercise_id) and per-constraint keys
    /// (constraint_type, hard, negated, source_text, value) are already in
    /// sort_keys order. Equipment ids are sorted ascending (ASCII => code-point order).
    public static func fingerprintPayload(availableEquipment: [String],
                                          constraints: [ResolvedConstraint],
                                          exerciseID: String) -> String {
        let eq = availableEquipment.sorted().map(encodeString).joined(separator: ",")
        let cons = constraints.map { c -> String in
            "{"
            + "\"constraint_type\":" + encodeString(c.constraintType) + ","
            + "\"hard\":" + (c.hard ? "true" : "false") + ","
            + "\"negated\":" + (c.negated ? "true" : "false") + ","
            + "\"source_text\":" + encodeString(c.sourceText) + ","
            + "\"value\":" + encodeString(c.value)
            + "}"
        }.joined(separator: ",")
        return "{"
            + "\"available_equipment\":[" + eq + "],"
            + "\"constraints\":[" + cons + "],"
            + "\"exercise_id\":" + encodeString(exerciseID)
            + "}"
    }

    public static func sha256Prefix16(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    public static func fingerprint(availableEquipment: [String],
                                   constraints: [ResolvedConstraint],
                                   exerciseID: String) -> String {
        sha256Prefix16(fingerprintPayload(availableEquipment: availableEquipment,
                                          constraints: constraints, exerciseID: exerciseID))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --disable-sandbox --filter CanonicalFingerprintTests`
Expected: PASS (2 tests). If the fingerprint assertions fail, the canonical string assertion will show the exact byte that diverges from Python — fix the encoder, not the expected value.

- [ ] **Step 5: Commit**

```bash
git add Sources/CamiFitKG/CanonicalJSON.swift Tests/CamiFitKGTests/CanonicalFingerprintTests.swift
git commit -m "feat(kgkit): canonical-JSON fingerprint with byte-exact Python parity"
```

---

### Task 8: `DecisionReceipt` + severity lattice

**Files:**
- Create: `Sources/CamiFitKG/DecisionReceipt.swift`
- Create: `Tests/CamiFitKGTests/SeverityLatticeTests.swift`

Port `DecisionReceipt`, `SEVERITY_LATTICE`, `HARD_BLOCK_SEVERITIES`, and `primary_severity` (`kg/safety.py`).

- [ ] **Step 1: Write the failing test**

Create `Tests/CamiFitKGTests/SeverityLatticeTests.swift`:

```swift
import XCTest
@testable import CamiFitKG

final class SeverityLatticeTests: XCTestCase {
    func testPrimarySeverityPicksMostSevere() {
        XCTAssertEqual(Severity.primary(["EQUIPMENT_HARD_BLOCK", "MEDICAL_HARD_BLOCK"]), "MEDICAL_HARD_BLOCK")
        XCTAssertEqual(Severity.primary(["SOFT_PENALTY", "PROMPT_EXCLUSION"]), "PROMPT_EXCLUSION")
        XCTAssertNil(Severity.primary(["NOT_A_SEVERITY"]))
    }

    func testHardBlockSet() {
        XCTAssertTrue(Severity.isHardBlock("EQUIPMENT_HARD_BLOCK"))
        XCTAssertFalse(Severity.isHardBlock("SOFT_PENALTY"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --disable-sandbox --filter SeverityLatticeTests`
Expected: FAIL — `cannot find 'Severity' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/CamiFitKG/DecisionReceipt.swift`:

```swift
/// Port of SEVERITY_LATTICE / HARD_BLOCK_SEVERITIES / primary_severity (kg/safety.py).
public enum Severity {
    public static let lattice = [
        "MEDICAL_HARD_BLOCK", "EQUIPMENT_HARD_BLOCK", "PROMPT_EXCLUSION",
        "MEMBER_STRONG_DISLIKE", "SOFT_PENALTY", "BOOST",
    ]
    public static let hardBlocks: Set<String> = [
        "MEDICAL_HARD_BLOCK", "EQUIPMENT_HARD_BLOCK", "PROMPT_EXCLUSION",
    ]
    public static func primary(_ reasons: [String]) -> String? {
        lattice.first { reasons.contains($0) }
    }
    public static func isHardBlock(_ severity: String) -> Bool { hardBlocks.contains(severity) }
}

/// Port of DecisionReceipt (kg/safety.py) — the 10 PROV_RECEIPT_REQUIRED_FIELDS.
public struct DecisionReceipt: Equatable, Sendable {
    public let exerciseID: String
    public let decision: String                // selected | filtered | downranked
    public let primarySeverity: String
    public let reasonCodes: [String]
    public let primaryReasonCode: String
    public let graphPaths: [String]
    public let constraintFingerprint: String
    public let graphVersion: String
    public let rulesetVersion: String
    public let ontologyLockVersion: String
}

/// One applicable reason before primary selection (kg/safety.py SafetyReason).
public struct SafetyReason: Equatable, Sendable {
    public let severity: String
    public let reasonCode: String
    public let graphPaths: [String]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --disable-sandbox --filter SeverityLatticeTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CamiFitKG/DecisionReceipt.swift Tests/CamiFitKGTests/SeverityLatticeTests.swift
git commit -m "feat(kgkit): DecisionReceipt + severity lattice"
```

---

### Task 9: Medical reason generator

**Files:**
- Create: `Sources/CamiFitKG/SafetyEngine.swift`
- Create: `Tests/CamiFitKGTests/MedicalReasonsTests.swift`

Port `_medical_reasons` + `_stress_hits_restriction` + `_restriction_applies_to_rule` + `_matches_properties` (`kg/safety.py`). `graphPaths = [stressEdge.path()] + restrictionPath + ruleUsesConceptPaths`.

- [ ] **Step 1: Write the failing test**

Create `Tests/CamiFitKGTests/MedicalReasonsTests.swift`:

```swift
import XCTest
@testable import CamiFitKG

final class MedicalReasonsTests: XCTestCase {
    private func engine() throws -> SafetyEngine {
        let artifact = try GraphArtifact.decode(from: Data(GraphArtifactDecodeTests.json.utf8))
        return SafetyEngine(graph: try LocalGraph(artifact: artifact), rules: artifact.safetyRules)
    }

    func testActiveKneeRestrictionBlocksLoadedDeepStress() throws {
        let knee = ResolvedConstraint(constraintType: "BodyRegion", value: "left_knee",
                                      hard: true, sourceText: "left knee")
        let reasons = try engine().medicalReasons(exerciseID: "Exercise:goblet_squat", constraints: [knee])
        XCTAssertEqual(reasons.count, 1)
        XCTAssertEqual(reasons[0].severity, "MEDICAL_HARD_BLOCK")
        XCTAssertEqual(reasons[0].reasonCode, "ACTIVE_KNEE_RESTRICTION")
        XCTAssertEqual(reasons[0].graphPaths, [
            "Exercise:goblet_squat -STRESSES-> BodyRegion:left_knee",
            "BodyRegion:left_knee -PART_OF-> BodyRegion:knee",
            "SafetyRule:avoid_loaded_knee_flexion -USES_CONCEPT-> BodyRegion:knee",
        ])
    }

    func testNoRestrictionMeansNoMedicalReason() throws {
        let reasons = try engine().medicalReasons(exerciseID: "Exercise:goblet_squat", constraints: [])
        XCTAssertEqual(reasons.count, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --disable-sandbox --filter MedicalReasonsTests`
Expected: FAIL — `cannot find 'SafetyEngine' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/CamiFitKG/SafetyEngine.swift`:

```swift
/// Deterministic safety evaluation over the local graph. Port of kg/safety.py.
/// The graph decides; no LLM, no vector search.
public struct SafetyEngine {
    public let graph: LocalGraph
    public let rules: [SafetyRule]

    public init(graph: LocalGraph, rules: [SafetyRule]) {
        self.graph = graph; self.rules = rules
    }

    // _matches_properties: every expected key must match the edge property.
    private func matches(edge: GraphEdge, rule: SafetyRule) -> Bool {
        guard rule.matchEdgePredicate == edge.predicate else { return false }
        for (key, expectation) in rule.matchProperties {
            if !expectation.matches(edge.properties[key]) { return false }
        }
        return true
    }

    // _stress_hits_restriction: [] if equal, path if a PART_OF path exists, nil otherwise.
    private func stressHitsRestriction(_ stressTarget: String, _ restrictionID: String) throws -> [String]? {
        if stressTarget == restrictionID { return [] }
        let path = try graph.partOfPath(from: stressTarget, to: restrictionID)
        return path.isEmpty ? nil : path
    }

    // _restriction_applies_to_rule: restriction is, or is PART_OF, one of the rule's concepts.
    private func restrictionAppliesToRule(_ restrictionID: String, _ rule: SafetyRule) throws -> Bool {
        for concept in rule.usesConcepts {
            if restrictionID == concept { return true }
            if try !graph.partOfPath(from: restrictionID, to: concept).isEmpty { return true }
        }
        return false
    }

    /// Port of _medical_reasons.
    public func medicalReasons(exerciseID: String, constraints: [ResolvedConstraint]) throws -> [SafetyReason] {
        let activeRestrictions = constraints
            .filter { $0.constraintType == "BodyRegion" && $0.hard && !$0.negated }
            .map { $0.nodeID }
        if activeRestrictions.isEmpty { return [] }

        var reasons: [SafetyReason] = []
        for stressEdge in graph.outgoing(exerciseID, predicate: "STRESSES") {
            for restrictionID in activeRestrictions {
                guard let restrictionPath = try stressHitsRestriction(stressEdge.target, restrictionID) else { continue }
                for rule in rules {
                    guard rule.severity == "MEDICAL_HARD_BLOCK" else { continue }
                    guard try restrictionAppliesToRule(restrictionID, rule) else { continue }
                    guard rule.matchEdgePredicate == "STRESSES" else { continue }
                    guard matches(edge: stressEdge, rule: rule) else { continue }
                    let rulePaths = rule.usesConcepts.map { "\(rule.id) -USES_CONCEPT-> \($0)" }
                    reasons.append(SafetyReason(
                        severity: rule.severity,
                        reasonCode: rule.reasonCode,
                        graphPaths: [stressEdge.path()] + restrictionPath + rulePaths))
                }
            }
        }
        return reasons
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --disable-sandbox --filter MedicalReasonsTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CamiFitKG/SafetyEngine.swift Tests/CamiFitKGTests/MedicalReasonsTests.swift
git commit -m "feat(kgkit): medical reason generator (knee STRESSES-rule match over PART_OF closure)"
```

---

### Task 10: Equipment + prompt-exclusion reason generators

**Files:**
- Modify: `Sources/CamiFitKG/SafetyEngine.swift`
- Create: `Tests/CamiFitKGTests/EquipmentAndExclusionReasonsTests.swift`

Port `_equipment_reasons` (REQUIRES not in available → `MISSING_EQUIPMENT`; in disallowed negated set → `DISALLOWED_EQUIPMENT`) and `_prompt_exclusion_reasons` (VARIANT_OF into excluded family → `PROMPT_EXCLUDED_FAMILY`).

- [ ] **Step 1: Write the failing test**

Create `Tests/CamiFitKGTests/EquipmentAndExclusionReasonsTests.swift`:

```swift
import XCTest
@testable import CamiFitKG

final class EquipmentAndExclusionReasonsTests: XCTestCase {
    // Local artifact: one barbell exercise requiring a barbell, plus a deadlift variant.
    static let json = """
    {"graph_version":"v","ruleset_version":"v","ontology_lock_version":"v",
     "nodes":[
       {"id":"Equipment:barbell","type":"Equipment","label":"Barbell","aliases":["barbell"]},
       {"id":"Equipment:dumbbell","type":"Equipment","label":"Dumbbell","aliases":["dumbbell"]},
       {"id":"ExerciseFamily:deadlift_family","type":"ExerciseFamily","label":"Deadlift Family","aliases":["deadlift"]},
       {"id":"Exercise:barbell_squat","type":"Exercise","label":"Barbell Squat","aliases":[]},
       {"id":"Exercise:kb_deadlift","type":"Exercise","label":"KB Deadlift","aliases":[]}
     ],
     "edges":[
       {"source":"Exercise:barbell_squat","predicate":"REQUIRES","target":"Equipment:barbell"},
       {"source":"Exercise:kb_deadlift","predicate":"VARIANT_OF","target":"ExerciseFamily:deadlift_family"}
     ],
     "safety_rules":[]}
    """
    private func engine() throws -> SafetyEngine {
        let a = try GraphArtifact.decode(from: Data(Self.json.utf8))
        return SafetyEngine(graph: try LocalGraph(artifact: a), rules: a.safetyRules)
    }

    func testMissingEquipmentWhenNotAvailable() throws {
        let r = try engine().equipmentReasons(exerciseID: "Exercise:barbell_squat",
                                              availableEquipment: ["Equipment:dumbbell"], constraints: [])
        XCTAssertEqual(r.map { $0.reasonCode }, ["MISSING_EQUIPMENT:barbell"])
        XCTAssertEqual(r[0].severity, "EQUIPMENT_HARD_BLOCK")
        XCTAssertEqual(r[0].graphPaths, ["Exercise:barbell_squat -REQUIRES-> Equipment:barbell"])
    }

    func testDisallowedEquipmentWhenNegatedConstraint() throws {
        let noBarbell = ResolvedConstraint(constraintType: "Equipment", value: "barbell",
                                           hard: true, sourceText: "no barbell", negated: true)
        let r = try engine().equipmentReasons(exerciseID: "Exercise:barbell_squat",
                                              availableEquipment: ["Equipment:barbell"], constraints: [noBarbell])
        XCTAssertEqual(r.map { $0.reasonCode }, ["DISALLOWED_EQUIPMENT:barbell"])
    }

    func testPromptExcludedFamily() throws {
        let exclude = ResolvedConstraint(constraintType: "ExerciseFamily", value: "deadlift_family",
                                         hard: true, sourceText: "exclude deadlifts", negated: true)
        let r = try engine().promptExclusionReasons(exerciseID: "Exercise:kb_deadlift", constraints: [exclude])
        XCTAssertEqual(r.map { $0.reasonCode }, ["PROMPT_EXCLUDED_FAMILY:deadlift_family"])
        XCTAssertEqual(r[0].severity, "PROMPT_EXCLUSION")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --disable-sandbox --filter EquipmentAndExclusionReasonsTests`
Expected: FAIL — `value of type 'SafetyEngine' has no member 'equipmentReasons'`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/CamiFitKG/SafetyEngine.swift` (inside the `SafetyEngine` struct):

```swift
    /// Port of _equipment_ids: normalize available equipment labels to node ids.
    public func equipmentIDs(_ available: [String]) -> Set<String> {
        Set(available.map { NodeID.make("Equipment", $0) })
    }

    /// Port of _equipment_reasons.
    public func equipmentReasons(exerciseID: String, availableEquipment: [String],
                                 constraints: [ResolvedConstraint]) -> [SafetyReason] {
        let available = equipmentIDs(availableEquipment)
        let disallowed = Set(constraints
            .filter { $0.constraintType == "Equipment" && $0.hard && $0.negated }
            .map { $0.nodeID })

        var reasons: [SafetyReason] = []
        for edge in graph.outgoing(exerciseID, predicate: "REQUIRES") {
            let value = edge.target.split(separator: ":", maxSplits: 1).last.map(String.init) ?? edge.target
            if !available.contains(edge.target) {
                reasons.append(SafetyReason(severity: "EQUIPMENT_HARD_BLOCK",
                    reasonCode: "MISSING_EQUIPMENT:\(value)", graphPaths: [edge.path()]))
            }
            if disallowed.contains(edge.target) {
                reasons.append(SafetyReason(severity: "EQUIPMENT_HARD_BLOCK",
                    reasonCode: "DISALLOWED_EQUIPMENT:\(value)", graphPaths: [edge.path()]))
            }
        }
        return reasons
    }

    /// Port of _prompt_exclusion_reasons.
    public func promptExclusionReasons(exerciseID: String, constraints: [ResolvedConstraint]) -> [SafetyReason] {
        let excluded = Set(constraints
            .filter { $0.constraintType == "ExerciseFamily" && $0.hard && $0.negated }
            .map { $0.nodeID })
        if excluded.isEmpty { return [] }

        var reasons: [SafetyReason] = []
        for edge in graph.outgoing(exerciseID, predicate: "VARIANT_OF") where excluded.contains(edge.target) {
            let value = edge.target.split(separator: ":", maxSplits: 1).last.map(String.init) ?? edge.target
            reasons.append(SafetyReason(severity: "PROMPT_EXCLUSION",
                reasonCode: "PROMPT_EXCLUDED_FAMILY:\(value)", graphPaths: [edge.path()]))
        }
        return reasons
    }
```

> Note on equipment normalization: `equipmentReasons` accepts raw labels (e.g. `"Dumbbell"`) and normalizes via `NodeID.make`, matching `_equipment_ids`. Tests above pass already-prefixed ids, which `NodeID.make` returns unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --disable-sandbox --filter EquipmentAndExclusionReasonsTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CamiFitKG/SafetyEngine.swift Tests/CamiFitKGTests/EquipmentAndExclusionReasonsTests.swift
git commit -m "feat(kgkit): equipment + prompt-exclusion reason generators"
```

---

### Task 11: Receipt assembly + `evaluateCandidates`

**Files:**
- Modify: `Sources/CamiFitKG/SafetyEngine.swift`
- Create: `Tests/CamiFitKGTests/EvaluateCandidatesTests.swift`

Port `_receipt` (compose reasons in order medical → equipment → prompt; pick primary by lattice; `filtered` if hard-block else `downranked`; no reasons → `selected`/`BOOST`/`PASSED_SAFETY`; fingerprint over the sorted-equipment + constraints payload) and `evaluate_candidates`.

- [ ] **Step 1: Write the failing test**

Create `Tests/CamiFitKGTests/EvaluateCandidatesTests.swift`:

```swift
import XCTest
@testable import CamiFitKG

final class EvaluateCandidatesTests: XCTestCase {
    private func engine() throws -> SafetyEngine {
        let a = try GraphArtifact.decode(from: Data(GraphArtifactDecodeTests.json.utf8))
        return SafetyEngine(graph: try LocalGraph(artifact: a), rules: a.safetyRules)
    }

    func testFilteredKneeReceiptHasFingerprintAndStamps() throws {
        let knee = ResolvedConstraint(constraintType: "BodyRegion", value: "left_knee",
                                      hard: true, sourceText: "left knee")
        let r = try engine().evaluateCandidates(["Exercise:goblet_squat"],
                                               availableEquipment: ["Dumbbell"], constraints: [knee])
        XCTAssertEqual(r.count, 1)
        let receipt = r[0]
        XCTAssertEqual(receipt.decision, "filtered")
        XCTAssertEqual(receipt.primarySeverity, "MEDICAL_HARD_BLOCK")
        XCTAssertEqual(receipt.reasonCodes, ["ACTIVE_KNEE_RESTRICTION"])
        XCTAssertEqual(receipt.primaryReasonCode, "ACTIVE_KNEE_RESTRICTION")
        XCTAssertEqual(receipt.graphVersion, CamiFitKG.graphVersion)
        XCTAssertEqual(receipt.constraintFingerprint.count, 16)
        // Fingerprint must equal the canonical computation for these exact inputs.
        XCTAssertEqual(receipt.constraintFingerprint,
            CanonicalJSON.fingerprint(availableEquipment: ["Equipment:dumbbell"],
                                      constraints: [knee], exerciseID: "Exercise:goblet_squat"))
    }

    func testSelectedReceiptWhenNoReasons() throws {
        let r = try engine().evaluateCandidates(["Exercise:goblet_squat"],
                                               availableEquipment: ["Dumbbell"], constraints: [])
        XCTAssertEqual(r[0].decision, "selected")
        XCTAssertEqual(r[0].primarySeverity, "BOOST")
        XCTAssertEqual(r[0].reasonCodes, ["PASSED_SAFETY"])
        XCTAssertEqual(r[0].graphPaths, [])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --disable-sandbox --filter EvaluateCandidatesTests`
Expected: FAIL — `value of type 'SafetyEngine' has no member 'evaluateCandidates'`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/CamiFitKG/SafetyEngine.swift` (inside the `SafetyEngine` struct):

```swift
    /// Port of _receipt.
    private func receipt(exerciseID: String, reasons: [SafetyReason],
                         availableEquipment: Set<String>, constraints: [ResolvedConstraint]) -> DecisionReceipt {
        let decision: String, severity: String, reasonCodes: [String], primaryReason: String, graphPaths: [String]
        if !reasons.isEmpty {
            severity = Severity.primary(reasons.map { $0.severity }) ?? "SOFT_PENALTY"
            primaryReason = reasons.first { $0.severity == severity }!.reasonCode
            decision = Severity.isHardBlock(severity) ? "filtered" : "downranked"
            reasonCodes = reasons.map { $0.reasonCode }
            graphPaths = reasons.flatMap { $0.graphPaths }
        } else {
            severity = "BOOST"; decision = "selected"
            reasonCodes = ["PASSED_SAFETY"]; primaryReason = "PASSED_SAFETY"; graphPaths = []
        }
        let fingerprint = CanonicalJSON.fingerprint(
            availableEquipment: Array(availableEquipment), constraints: constraints, exerciseID: exerciseID)
        return DecisionReceipt(
            exerciseID: exerciseID, decision: decision, primarySeverity: severity,
            reasonCodes: reasonCodes, primaryReasonCode: primaryReason, graphPaths: graphPaths,
            constraintFingerprint: fingerprint, graphVersion: CamiFitKG.graphVersion,
            rulesetVersion: CamiFitKG.rulesetVersion, ontologyLockVersion: CamiFitKG.ontologyLockVersion)
    }

    /// Port of evaluate_candidates. When candidateIDs is nil, evaluate all Exercise nodes sorted by id.
    public func evaluateCandidates(_ candidateIDs: [String]? = nil, availableEquipment: [String],
                                   constraints: [ResolvedConstraint]) throws -> [DecisionReceipt] {
        let available = equipmentIDs(availableEquipment)
        let exercises = candidateIDs ?? graph.nodesByType("Exercise").map { $0.id }
        var receipts: [DecisionReceipt] = []
        for exerciseID in exercises {
            try graph.requireNode(exerciseID)
            let reasons = try medicalReasons(exerciseID: exerciseID, constraints: constraints)
                + equipmentReasons(exerciseID: exerciseID, availableEquipment: availableEquipment, constraints: constraints)
                + promptExclusionReasons(exerciseID: exerciseID, constraints: constraints)
            receipts.append(receipt(exerciseID: exerciseID, reasons: reasons,
                                    availableEquipment: available, constraints: constraints))
        }
        return receipts
    }
```

> `availableEquipment` for the fingerprint is `Array(available)` (the normalized id set); `CanonicalJSON.fingerprintPayload` sorts it, exactly as `_receipt` does `sorted(available_equipment)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --disable-sandbox --filter EvaluateCandidatesTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/CamiFitKG/SafetyEngine.swift Tests/CamiFitKGTests/EvaluateCandidatesTests.swift
git commit -m "feat(kgkit): receipt assembly + evaluateCandidates"
```

---

### Task 12: Conformance-vector harness (byte-exact parity vs the Python oracle)

**Files:**
- Modify: `scripts/gen_kg_conformance_vectors.py`
- Create (generated): `Tests/CamiFitKGTests/Fixtures/conformance/safety_vectors.json`
- Create: `Sources/CamiFitKG/ArtifactLoader.swift`
- Create: `Tests/CamiFitKGTests/ConformanceTests.swift`

The generator now runs FitGraph's **live oracle** over scenarios and freezes each receipt as a vector. The Swift test loads the **same bundled artifact**, replays each vector, and asserts every field — proving on-device parity. This is the deliverable.

- [ ] **Step 1: Extend the generator to emit vectors**

Append to `scripts/gen_kg_conformance_vectors.py` (before the `if __name__` block):

```python
from kg.constraints import ResolvedConstraint  # noqa: E402
from kg.safety import evaluate_candidates  # noqa: E402
from dataclasses import asdict  # noqa: E402

VECTORS = REPO / "Tests/CamiFitKGTests/Fixtures/conformance/safety_vectors.json"


def _c(**kw) -> ResolvedConstraint:
    base = dict(constraint_type="", value="", hard=False, source_text="")
    base.update(kw)
    return ResolvedConstraint(**base)


def emit_vectors() -> None:
    graph = load_local_graph(FITGRAPH / "graph" / "exercise_kg.seed.json")
    rules = load_safety_rules(FITGRAPH / "graph")
    jordan_equipment = ["Dumbbell", "Kettlebell", "Yoga Mat"]
    scenarios = [
        {"name": "knee_restriction", "available_equipment": jordan_equipment,
         "constraints": [_c(constraint_type="BodyRegion", value="left_knee", hard=True, source_text="left knee")]},
        {"name": "no_barbell", "available_equipment": jordan_equipment,
         "constraints": [_c(constraint_type="Equipment", value="barbell", hard=True, negated=True, source_text="no barbell")]},
        {"name": "exclude_deadlifts", "available_equipment": jordan_equipment,
         "constraints": [_c(constraint_type="ExerciseFamily", value="deadlift_family", hard=True, negated=True, source_text="exclude deadlifts")]},
        {"name": "clean", "available_equipment": jordan_equipment, "constraints": []},
    ]
    vectors = []
    for sc in scenarios:
        receipts = evaluate_candidates(
            available_equipment=sc["available_equipment"],
            constraints=tuple(sc["constraints"]), graph=graph, safety_rules=rules)
        for r in receipts:
            vectors.append({
                "scenario": sc["name"],
                "input": {
                    "available_equipment": sc["available_equipment"],
                    "constraints": [
                        {"constraint_type": c.constraint_type, "value": c.value, "hard": c.hard,
                         "source_text": c.source_text, "negated": c.negated} for c in sc["constraints"]
                    ],
                    "exercise_id": r.exercise_id,
                },
                "expected": {
                    "decision": r.decision, "primary_severity": r.primary_severity,
                    "reason_codes": list(r.reason_codes), "primary_reason_code": r.primary_reason_code,
                    "graph_paths": list(r.graph_paths), "constraint_fingerprint": r.constraint_fingerprint,
                    "graph_version": r.graph_version, "ruleset_version": r.ruleset_version,
                    "ontology_lock_version": r.ontology_lock_version,
                },
            })
    VECTORS.parent.mkdir(parents=True, exist_ok=True)
    VECTORS.write_text(json.dumps({"vectors": vectors}, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {VECTORS.relative_to(REPO)}: {len(vectors)} vectors")
```

Change the `__main__` block to:

```python
if __name__ == "__main__":
    freeze_artifact()
    emit_vectors()
```

- [ ] **Step 2: Generate the artifact + vectors**

Run: `FITGRAPH=/Users/kelly/Developer/fitgraph python3 scripts/gen_kg_conformance_vectors.py`
Expected: two `wrote …` lines; `safety_vectors.json` now holds one vector per (scenario × seed exercise).

- [ ] **Step 3: Write the failing test + the bundled-artifact loader**

Create `Sources/CamiFitKG/ArtifactLoader.swift`:

```swift
import Foundation

public enum ArtifactLoader {
    public enum LoadError: Error { case missingResource }

    /// Load the frozen artifact bundled into the CamiFitKG module.
    public static func bundled() throws -> GraphArtifact {
        guard let url = Bundle.module.url(forResource: "kg_artifact.v0", withExtension: "json",
                                          subdirectory: "Artifact") else {
            throw LoadError.missingResource
        }
        return try GraphArtifact.decode(from: Data(contentsOf: url))
    }
}
```

Create `Tests/CamiFitKGTests/ConformanceTests.swift`:

```swift
import XCTest
@testable import CamiFitKG

final class ConformanceTests: XCTestCase {
    struct Vector: Decodable {
        struct Constraint: Decodable {
            let constraint_type: String, value: String, hard: Bool, source_text: String, negated: Bool
        }
        struct Input: Decodable {
            let available_equipment: [String]; let constraints: [Constraint]; let exercise_id: String
        }
        struct Expected: Decodable {
            let decision: String, primary_severity: String
            let reason_codes: [String], primary_reason_code: String, graph_paths: [String]
            let constraint_fingerprint: String, graph_version: String, ruleset_version: String, ontology_lock_version: String
        }
        let scenario: String, input: Input, expected: Expected
    }

    func testSwiftRuntimeReproducesEveryOracleReceipt() throws {
        let artifact = try ArtifactLoader.bundled()
        let engine = SafetyEngine(graph: try LocalGraph(artifact: artifact), rules: artifact.safetyRules)

        let url = Bundle.module.url(forResource: "safety_vectors", withExtension: "json",
                                    subdirectory: "Fixtures/conformance")!
        let payload = try JSONDecoder().decode([String: [Vector]].self, from: Data(contentsOf: url))
        let vectors = payload["vectors"] ?? []
        XCTAssertGreaterThan(vectors.count, 0, "no vectors loaded")

        for v in vectors {
            let constraints = v.input.constraints.map {
                ResolvedConstraint(constraintType: $0.constraint_type, value: $0.value, hard: $0.hard,
                                   sourceText: $0.source_text, negated: $0.negated)
            }
            let got = try engine.evaluateCandidates([v.input.exercise_id],
                availableEquipment: v.input.available_equipment, constraints: constraints)[0]
            let e = v.expected
            let ctx = "\(v.scenario)/\(v.input.exercise_id)"
            XCTAssertEqual(got.decision, e.decision, ctx)
            XCTAssertEqual(got.primarySeverity, e.primary_severity, ctx)
            XCTAssertEqual(got.reasonCodes, e.reason_codes, ctx)
            XCTAssertEqual(got.primaryReasonCode, e.primary_reason_code, ctx)
            XCTAssertEqual(got.graphPaths, e.graph_paths, ctx)
            XCTAssertEqual(got.constraintFingerprint, e.constraint_fingerprint, "FINGERPRINT \(ctx)")
            XCTAssertEqual(got.graphVersion, e.graph_version, ctx)
            XCTAssertEqual(got.rulesetVersion, e.ruleset_version, ctx)
            XCTAssertEqual(got.ontologyLockVersion, e.ontology_lock_version, ctx)
        }
    }
}
```

- [ ] **Step 4: Run the test to verify parity**

Run: `swift test --disable-sandbox --filter ConformanceTests`
Expected: PASS. Every seed exercise across all four scenarios produces a Swift receipt identical to the Python oracle, including the `constraint_fingerprint`. A `FINGERPRINT …` failure means the canonical encoder (Task 7) diverges — fix the encoder, never the vector.

- [ ] **Step 5: Commit**

```bash
git add scripts/gen_kg_conformance_vectors.py Tests/CamiFitKGTests/Fixtures/conformance/safety_vectors.json Sources/CamiFitKG/ArtifactLoader.swift Tests/CamiFitKGTests/ConformanceTests.swift
git commit -m "feat(kgkit): conformance-vector harness proving byte-exact oracle parity"
```

---

### Task 13: Module README + full-suite green gate

**Files:**
- Create: `Sources/CamiFitKG/README.md`
- Test: full `CamiFitKG` suite

- [ ] **Step 1: Write the README**

Create `Sources/CamiFitKG/README.md`:

```markdown
# CamiFitKG — on-device deterministic safety runtime

Swift port of FitGraph's deterministic safety-by-traversal. The graph decides
eligibility; no LLM, no vector search. Loads a frozen graph artifact
(`Resources/Artifact/kg_artifact.v0.json`, generated by
`scripts/gen_kg_conformance_vectors.py` from the FitGraph seed) and reproduces
the Python oracle's `DecisionReceipt`s byte-for-byte — including the
`sha256[:16]` `constraint_fingerprint` — verified by `ConformanceTests`.

## Regenerating the artifact + vectors
    FITGRAPH=/Users/kelly/Developer/fitgraph python3 scripts/gen_kg_conformance_vectors.py
    swift test --disable-sandbox --filter CamiFitKGTests

## What is NOT here yet (see docs/superpowers/plans/)
Resolver, alternatives, member retrieval, 50-exercise scale-up, monorepo migration.
Scope and rationale: docs/design/2026-06-04-camifit-fitgraph-synthesis.md.
```

- [ ] **Step 2: Run the full module suite**

Run: `swift test --disable-sandbox --filter CamiFitKGTests`
Expected: PASS — all tests from Tasks 1–12 green.

- [ ] **Step 3: Run the entire package suite (no regressions elsewhere)**

Run: `swift test --disable-sandbox`
Expected: PASS — existing `CamiFitEngineTests` / `CamiFitAppTests` unaffected, plus the new `CamiFitKGTests`.

- [ ] **Step 4: Commit**

```bash
git add Sources/CamiFitKG/README.md
git commit -m "docs(kgkit): module README + safety-core milestone"
```

---

## Self-review (completed during authoring)

- **Spec coverage:** This plan implements synthesis §4 (Swift serving runtime + conformance parity), §5 Contract 2 (the `DecisionReceipt` shape, ported verbatim), and the deterministic safety half of §6 — for the medical/equipment/exclusion blocks. Resolver (§5 resolve), alternatives, member retrieval, the 50-exercise catalog (§5 Contract 1), the closed execution loop's compile/write-back (§6.3–§6.6), and the monorepo (§8) are explicitly deferred to named follow-on plans.
- **No placeholders:** every code step contains complete code. The only intentional fill-ins are the two Python-generated fingerprint expectations in Task 7 (`EXPECTED_ASCII_FP` / `EXPECTED_UNICODE_FP`) and the generated artifact/vector JSON — each with the exact command to produce them.
- **Type consistency:** `GraphNode`/`GraphEdge`/`PropertyValue` (Task 2) → `GraphArtifact`/`SafetyRule`/`RuleMatch` (Task 3) → `LocalGraph` (Tasks 4–5) → `ResolvedConstraint`/`NodeID` (Task 6) → `CanonicalJSON` (Task 7) → `DecisionReceipt`/`Severity`/`SafetyReason` (Task 8) → `SafetyEngine` (Tasks 9–11) → `ArtifactLoader`/`ConformanceTests` (Task 12). `evaluateCandidates(_:availableEquipment:constraints:)` is used identically in Tasks 11 and 12.
- **Determinism parity:** sorted `nodesByType`, BFS `partOfPath` (edges sorted by target), DFS `partOfClosurePaths` (edges sorted by source), reason order medical→equipment→prompt, and sorted-equipment fingerprint payload all mirror the Python source line-for-line.
