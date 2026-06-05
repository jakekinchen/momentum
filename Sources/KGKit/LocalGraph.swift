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
