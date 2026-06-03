import Foundation

public enum SignalValue: Equatable, CustomStringConvertible {
    case valid(Double, confidence: Double)
    case invalid(reason: String)

    public var description: String {
        switch self {
        case let .valid(value, confidence):
            return String(format: "valid(%.3f, confidence: %.3f)", value, confidence)
        case let .invalid(reason):
            return "invalid(\(reason))"
        }
    }

    public var numericValue: Double? {
        switch self {
        case let .valid(value, _):
            return value
        case .invalid:
            return nil
        }
    }
}
