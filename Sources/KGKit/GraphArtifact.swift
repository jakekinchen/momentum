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
