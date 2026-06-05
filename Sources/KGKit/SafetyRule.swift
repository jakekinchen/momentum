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
