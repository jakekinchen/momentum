import Foundation

public struct FormRuleSnapshot: Equatable, CustomStringConvertible {
    public let ruleID: String
    public let isActive: Bool
    public let expectationPassed: Bool?
    public let cue: String?
    public let severity: RuleSeverity
    public let invalidReason: String?

    public var description: String {
        var parts = [
            "id=\(ruleID)",
            "active=\(isActive)",
            "passed=\(expectationPassed.map(String.init) ?? "nil")",
            "severity=\(severity.rawValue)"
        ]

        if let cue {
            parts.append("cue=\(cue)")
        }

        if let invalidReason {
            parts.append("invalid=\(invalidReason)")
        }

        return parts.joined(separator: " ")
    }
}

public enum FormRuleEvaluatorError: Error, Equatable, CustomStringConvertible {
    case parseError(ruleID: String, field: String, reason: String)

    public var description: String {
        switch self {
        case let .parseError(ruleID, field, reason):
            return "parse_error(rule: \(ruleID), field: \(field), reason: \(reason))"
        }
    }
}

public struct FormRuleEvaluator {
    public let ruleIDs: [String]

    private let compiledRules: [CompiledFormRule]
    private let minSignalConfidence: Double

    public init(program: ExerciseProgram) throws {
        var compiledRules: [CompiledFormRule] = []

        for rule in program.formRules {
            let condition: FormRuleCondition
            do {
                condition = try FormRuleCondition.parse(rule.when)
            } catch {
                throw FormRuleEvaluatorError.parseError(
                    ruleID: rule.id,
                    field: "when",
                    reason: String(describing: error)
                )
            }

            let expectation: PredicateExpression
            do {
                var parser = try ExpressionParser(rule.expect)
                expectation = try parser.parsePredicate()
            } catch {
                throw FormRuleEvaluatorError.parseError(
                    ruleID: rule.id,
                    field: "expect",
                    reason: String(describing: error)
                )
            }

            compiledRules.append(CompiledFormRule(rule: rule, condition: condition, expectation: expectation))
        }

        self.compiledRules = compiledRules
        ruleIDs = compiledRules.map(\.rule.id)
        minSignalConfidence = program.validity.minSignalConfidence
    }

    public func evaluate(
        producedValues: [String: SignalValue],
        phase: RepPhase,
        frame: PoseFrame? = nil
    ) -> [FormRuleSnapshot] {
        compiledRules.map { compiledRule in
            evaluate(compiledRule, producedValues: producedValues, phase: phase, frame: frame)
        }
    }

    private func evaluate(
        _ compiledRule: CompiledFormRule,
        producedValues: [String: SignalValue],
        phase: RepPhase,
        frame: PoseFrame?
    ) -> FormRuleSnapshot {
        let rule = compiledRule.rule
        let isActive = compiledRule.condition.matches(phase)

        guard isActive else {
            return FormRuleSnapshot(
                ruleID: rule.id,
                isActive: false,
                expectationPassed: nil,
                cue: nil,
                severity: rule.severity,
                invalidReason: nil
            )
        }

        let result = evaluate(
            compiledRule.expectation,
            producedValues: producedValues,
            frame: frame ?? Self.emptyFrame
        )

        switch result {
        case .satisfied:
            return FormRuleSnapshot(
                ruleID: rule.id,
                isActive: true,
                expectationPassed: true,
                cue: nil,
                severity: rule.severity,
                invalidReason: nil
            )
        case .unsatisfied:
            return FormRuleSnapshot(
                ruleID: rule.id,
                isActive: true,
                expectationPassed: false,
                cue: rule.cue,
                severity: rule.severity,
                invalidReason: nil
            )
        case let .invalid(reason):
            return FormRuleSnapshot(
                ruleID: rule.id,
                isActive: true,
                expectationPassed: nil,
                cue: nil,
                severity: rule.severity,
                invalidReason: reason
            )
        }
    }

    private func evaluate(
        _ predicate: PredicateExpression,
        producedValues: [String: SignalValue],
        frame: PoseFrame
    ) -> PredicateResult {
        let evaluator = ExpressionEvaluator(
            frame: frame,
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
            return .invalid(reason: "\(side) form-rule operand did not evaluate to a numeric value")
        case let .invalid(reason):
            return .invalid(reason: reason)
        }
    }

    private static let equalityTolerance = 1e-9

    private static let emptyFrame = PoseFrame(timestampMS: 0, imageWidth: 0, imageHeight: 0, landmarks: [:])
}

private struct CompiledFormRule {
    let rule: FormRule
    let condition: FormRuleCondition
    let expectation: PredicateExpression
}

private enum FormRuleCondition: Equatable {
    case phaseEquals(RepPhase)
    case phaseIn(Set<RepPhase>)

    static func parse(_ source: String) throws -> FormRuleCondition {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)

        if let rawPhase = parsePhaseEquality(trimmed) {
            guard let phase = RepPhase(rawValue: rawPhase) else {
                throw FormRuleConditionParseError.unknownPhase(rawPhase)
            }

            return .phaseEquals(phase)
        }

        if let rawPhases = parsePhaseMembership(trimmed) {
            let phases = try rawPhases.map { rawPhase in
                guard let phase = RepPhase(rawValue: rawPhase) else {
                    throw FormRuleConditionParseError.unknownPhase(rawPhase)
                }

                return phase
            }

            return .phaseIn(Set(phases))
        }

        throw FormRuleConditionParseError.unsupported(source)
    }

    func matches(_ phase: RepPhase) -> Bool {
        switch self {
        case let .phaseEquals(expected):
            return phase == expected
        case let .phaseIn(phases):
            return phases.contains(phase)
        }
    }

    private static func parsePhaseEquality(_ source: String) -> String? {
        let prefix = "phase == "
        guard source.hasPrefix(prefix) else {
            return nil
        }

        return parseSingleQuotedString(String(source.dropFirst(prefix.count)))
    }

    private static func parsePhaseMembership(_ source: String) -> [String]? {
        let prefix = "phase in ["
        guard source.hasPrefix(prefix), source.hasSuffix("]") else {
            return nil
        }

        let inner = source
            .dropFirst(prefix.count)
            .dropLast()

        return inner.split(separator: ",").compactMap { part in
            parseSingleQuotedString(String(part).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func parseSingleQuotedString(_ source: String) -> String? {
        guard source.first == "'", source.last == "'", source.count >= 2 else {
            return nil
        }

        return String(source.dropFirst().dropLast())
    }
}

private enum FormRuleConditionParseError: Error, Equatable, CustomStringConvertible {
    case unsupported(String)
    case unknownPhase(String)

    var description: String {
        switch self {
        case let .unsupported(source):
            return "unsupported condition \(source)"
        case let .unknownPhase(phase):
            return "unknown phase \(phase)"
        }
    }
}
