import Foundation

public enum PredicateResult: Equatable, CustomStringConvertible {
    case satisfied
    case unsatisfied
    case invalid(reason: String)

    public var description: String {
        switch self {
        case .satisfied:
            return "true"
        case .unsatisfied:
            return "false"
        case let .invalid(reason):
            return "invalid(\(reason))"
        }
    }
}

public struct RepPredicateEvaluator {
    private let downPredicate: PredicateExpression
    private let upPredicate: PredicateExpression
    private let minSignalConfidence: Double

    public init(program: ExerciseProgram) throws {
        guard let rep = program.rep else {
            throw ProgramLoadError.invalidStructure(field: "rep", reason: "rep predicate evaluator requires rep config")
        }

        try self.init(
            downWhen: rep.downWhen,
            upWhen: rep.upWhen,
            minSignalConfidence: program.validity.minSignalConfidence
        )
    }

    public init(downWhen: String, upWhen: String, minSignalConfidence: Double) throws {
        var downParser = try ExpressionParser(downWhen)
        var upParser = try ExpressionParser(upWhen)
        downPredicate = try downParser.parsePredicate()
        upPredicate = try upParser.parsePredicate()
        self.minSignalConfidence = minSignalConfidence
    }

    public func evaluateDown(
        producedValues: [String: SignalValue],
        frame: PoseFrame? = nil
    ) -> PredicateResult {
        evaluate(downPredicate, producedValues: producedValues, frame: frame)
    }

    public func evaluateUp(
        producedValues: [String: SignalValue],
        frame: PoseFrame? = nil
    ) -> PredicateResult {
        evaluate(upPredicate, producedValues: producedValues, frame: frame)
    }

    private func evaluate(
        _ predicate: PredicateExpression,
        producedValues: [String: SignalValue],
        frame: PoseFrame?
    ) -> PredicateResult {
        let evaluator = ExpressionEvaluator(
            frame: frame ?? Self.emptyFrame,
            signals: producedValues,
            minConfidence: minSignalConfidence
        )

        let left = evaluator.evaluate(predicate.left)
        let right = evaluator.evaluate(predicate.right)

        guard case let .valid(leftValue, _) = left else {
            return invalidResult(from: left, side: "left")
        }

        guard case let .valid(rightValue, _) = right else {
            return invalidResult(from: right, side: "right")
        }

        let matched: Bool
        switch predicate.comparison {
        case .lessThan:
            matched = leftValue < rightValue
        case .lessThanOrEqual:
            matched = leftValue <= rightValue
        case .greaterThan:
            matched = leftValue > rightValue
        case .greaterThanOrEqual:
            matched = leftValue >= rightValue
        case .equal:
            matched = abs(leftValue - rightValue) <= Self.equalityTolerance
        case .notEqual:
            matched = abs(leftValue - rightValue) > Self.equalityTolerance
        }

        return matched ? .satisfied : .unsatisfied
    }

    private func invalidResult(from value: SignalValue, side: String) -> PredicateResult {
        switch value {
        case .valid:
            return .invalid(reason: "\(side) predicate operand did not evaluate to a numeric value")
        case let .invalid(reason):
            return .invalid(reason: reason)
        }
    }

    private static let equalityTolerance = 1e-9

    private static let emptyFrame = PoseFrame(timestampMS: 0, imageWidth: 0, imageHeight: 0, landmarks: [:])
}
