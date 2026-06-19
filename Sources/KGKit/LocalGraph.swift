public struct LocalGraph: Sendable {
    public let graphVersion: String
    public let rulesetVersion: String
    public let ontologyLockVersion: String
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
        self.graphVersion = artifact.graphVersion
        self.rulesetVersion = artifact.rulesetVersion
        self.ontologyLockVersion = artifact.ontologyLockVersion
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
}
