/// Property values in the seed graph are JSON scalars (string/bool/number).
/// A small closed enum keeps edge property matching deterministic and type-safe.
public enum PropertyValue: Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case double(Double)
    case null
}

extension PropertyValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
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
