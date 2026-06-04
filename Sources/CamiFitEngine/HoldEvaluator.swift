import Foundation

public struct HoldSnapshot: Equatable, CustomStringConvertible {
    public let heldSeconds: Double
    public let inRange: Bool
    public let valid: Bool
    public let targetReached: Bool
    public let notAccumulatingReason: String?

    public var description: String {
        var parts = [
            String(format: "held=%.3f", heldSeconds),
            "in_range=\(inRange)",
            "valid=\(valid)",
            "target=\(targetReached)"
        ]

        if let notAccumulatingReason {
            parts.append("reason=\(notAccumulatingReason)")
        }

        return parts.joined(separator: " ")
    }
}

public struct HoldEvaluator {
    private let hold: HoldConfig
    private let inRangePredicate: PredicateExpression
    private let minSignalConfidence: Double
    private let maxAccumulatedDeltaMS: Int64
    private var heldSeconds = 0.0
    private var lastAccumulatingTimestampMS: Int64?

    public init(program: ExerciseProgram, maxAccumulatedDeltaMS: Int64 = 500) throws {
        guard let hold = program.hold else {
            throw ProgramLoadError.invalidStructure(field: "hold", reason: "hold evaluator requires hold config")
        }

        try self.init(
            hold: hold,
            minSignalConfidence: program.validity.minSignalConfidence,
            maxAccumulatedDeltaMS: maxAccumulatedDeltaMS
        )
    }

    public init(hold: HoldConfig, minSignalConfidence: Double, maxAccumulatedDeltaMS: Int64 = 500) throws {
        var parser = try ExpressionParser(hold.inRange)
        inRangePredicate = try parser.parsePredicate()
        self.hold = hold
        self.minSignalConfidence = minSignalConfidence
        self.maxAccumulatedDeltaMS = max(0, maxAccumulatedDeltaMS)
    }

    public mutating func update(
        timestampMS: Int64,
        producedValues: [String: SignalValue],
        frame: PoseFrame? = nil
    ) -> HoldSnapshot {
        guard let signal = producedValues[hold.signal] else {
            return resetSnapshot(reason: "missing hold signal \(hold.signal)")
        }

        guard case let .valid(signalValue, _) = signal, signalValue.isFinite else {
            return resetSnapshot(reason: invalidSignalReason(signal))
        }

        let rangeResult = evaluateInRange(producedValues: producedValues, frame: frame)
        switch rangeResult {
        case .satisfied:
            break
        case .unsatisfied:
            heldSeconds = 0
            lastAccumulatingTimestampMS = nil
            return snapshot(inRange: false, valid: true, reason: notAccumulatingReason(for: rangeResult))
        case .invalid:
            return resetSnapshot(reason: notAccumulatingReason(for: rangeResult))
        }

        if let lastAccumulatingTimestampMS {
            let deltaMS = max(0, timestampMS - lastAccumulatingTimestampMS)
            heldSeconds += Double(min(deltaMS, maxAccumulatedDeltaMS)) / 1_000.0
        }

        lastAccumulatingTimestampMS = timestampMS
        return snapshot(inRange: true, valid: true, reason: nil)
    }

    private mutating func resetSnapshot(reason: String) -> HoldSnapshot {
        heldSeconds = 0
        lastAccumulatingTimestampMS = nil
        return snapshot(inRange: false, valid: false, reason: reason)
    }

    private func snapshot(inRange: Bool, valid: Bool, reason: String?) -> HoldSnapshot {
        HoldSnapshot(
            heldSeconds: heldSeconds,
            inRange: inRange,
            valid: valid,
            targetReached: heldSeconds >= hold.targetSeconds,
            notAccumulatingReason: reason
        )
    }

    private func evaluateInRange(
        producedValues: [String: SignalValue],
        frame: PoseFrame?
    ) -> PredicateResult {
        let evaluator = ExpressionEvaluator(
            frame: frame ?? Self.emptyFrame,
            signals: producedValues,
            minConfidence: minSignalConfidence
        )
        let left = evaluator.evaluate(inRangePredicate.left)
        let right = evaluator.evaluate(inRangePredicate.right)

        guard case let .valid(leftValue, _) = left else {
            return invalidResult(from: left, side: "left")
        }

        guard case let .valid(rightValue, _) = right else {
            return invalidResult(from: right, side: "right")
        }

        let matched: Bool
        switch inRangePredicate.comparison {
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
            return .invalid(reason: "\(side) hold predicate operand did not evaluate to a numeric value")
        case let .invalid(reason):
            return .invalid(reason: reason)
        }
    }

    private func invalidSignalReason(_ signal: SignalValue) -> String {
        switch signal {
        case let .invalid(reason):
            return "hold signal \(hold.signal) invalid: \(reason)"
        case let .valid(value, _):
            return "hold signal \(hold.signal) invalid: non-finite value \(value)"
        }
    }

    private func notAccumulatingReason(for result: PredicateResult) -> String {
        switch result {
        case .satisfied:
            return "in range"
        case .unsatisfied:
            return "hold signal \(hold.signal) out of range"
        case let .invalid(reason):
            return "hold predicate invalid: \(reason)"
        }
    }

    private static let equalityTolerance = 1e-9

    private static let emptyFrame = PoseFrame(timestampMS: 0, imageWidth: 0, imageHeight: 0, landmarks: [:])
}
