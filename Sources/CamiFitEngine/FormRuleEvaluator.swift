import Foundation

public struct FormRuleSnapshot: Equatable, CustomStringConvertible {
    public let ruleID: String
    public let isActive: Bool
    public let expectationPassed: Bool?
    public let cue: String?
    public let severity: RuleSeverity
    public let violationDurationMS: Int?
    public let cueCooldownRemainingMS: Int?
    public let invalidReason: String?

    public var description: String {
        var parts = [
            "id=\(ruleID)",
            "active=\(isActive)",
            "passed=\(expectationPassed.map(String.init) ?? "nil")",
            "severity=\(severity.rawValue)"
        ]

        if let violationDurationMS {
            parts.append("violation_ms=\(violationDurationMS)")
        }

        if let cueCooldownRemainingMS {
            parts.append("cue_cooldown_ms=\(cueCooldownRemainingMS)")
        }

        if let cue {
            parts.append("cue=\(cue)")
        }

        if let invalidReason {
            parts.append("invalid=\(invalidReason)")
        }

        return parts.joined(separator: " ")
    }
}

public struct FormRuleScoreSummary: Equatable, CustomStringConvertible {
    public let score: Double?
    public let earnedWeight: Double
    public let possibleWeight: Double
    public let activeRuleCount: Int
    public let scoredRuleCount: Int
    public let invalidActiveRuleCount: Int
    public let selectedCue: String?
    public let selectedCueRuleID: String?

    public var description: String {
        let scoreDescription = score.map { String(format: "%.3f", $0) } ?? "nil"
        var parts = [
            "score=\(scoreDescription)",
            "earned_weight=\(String(format: "%.3f", earnedWeight))",
            "possible_weight=\(String(format: "%.3f", possibleWeight))",
            "active_rules=\(activeRuleCount)",
            "scored_rules=\(scoredRuleCount)",
            "invalid_active_rules=\(invalidActiveRuleCount)"
        ]

        if let selectedCueRuleID, let selectedCue {
            parts.append("cue_rule=\(selectedCueRuleID)")
            parts.append("cue=\(selectedCue)")
        }

        return parts.joined(separator: " ")
    }
}

public struct FormRuleScoreSummarizer {
    private let ruleMetadataByID: [String: FormRuleSummaryMetadata]

    public init(program: ExerciseProgram) {
        var metadata: [String: FormRuleSummaryMetadata] = [:]
        for (index, rule) in program.formRules.enumerated() {
            metadata[rule.id] = FormRuleSummaryMetadata(
                weight: rule.scoreWeight,
                severity: rule.severity,
                order: index
            )
        }
        ruleMetadataByID = metadata
    }

    public func summarize(_ snapshots: [FormRuleSnapshot]) -> FormRuleScoreSummary {
        var earnedWeight = 0.0
        var possibleWeight = 0.0
        var activeRuleCount = 0
        var scoredRuleCount = 0
        var invalidActiveRuleCount = 0
        var selectedCueCandidate: FormRuleCueCandidate?

        for snapshot in snapshots {
            let metadata = ruleMetadataByID[snapshot.ruleID] ?? FormRuleSummaryMetadata(
                weight: 0,
                severity: snapshot.severity,
                order: Int.max
            )

            if snapshot.isActive {
                activeRuleCount += 1

                switch snapshot.expectationPassed {
                case .some(true):
                    possibleWeight += metadata.weight
                    earnedWeight += metadata.weight
                    scoredRuleCount += 1
                case .some(false):
                    possibleWeight += metadata.weight
                    scoredRuleCount += 1
                case .none:
                    invalidActiveRuleCount += 1
                }
            }

            guard let cue = snapshot.cue else {
                continue
            }

            let candidate = FormRuleCueCandidate(
                ruleID: snapshot.ruleID,
                cue: cue,
                severity: snapshot.severity,
                weight: metadata.weight,
                order: metadata.order
            )

            if selectedCueCandidate.map({ candidate.hasPriority(over: $0) }) ?? true {
                selectedCueCandidate = candidate
            }
        }

        let score = possibleWeight > 0 ? earnedWeight / possibleWeight : nil

        return FormRuleScoreSummary(
            score: score,
            earnedWeight: earnedWeight,
            possibleWeight: possibleWeight,
            activeRuleCount: activeRuleCount,
            scoredRuleCount: scoredRuleCount,
            invalidActiveRuleCount: invalidActiveRuleCount,
            selectedCue: selectedCueCandidate?.cue,
            selectedCueRuleID: selectedCueCandidate?.ruleID
        )
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

private struct FormRuleSummaryMetadata {
    let weight: Double
    let severity: RuleSeverity
    let order: Int
}

private struct FormRuleCueCandidate {
    let ruleID: String
    let cue: String
    let severity: RuleSeverity
    let weight: Double
    let order: Int

    func hasPriority(over other: FormRuleCueCandidate) -> Bool {
        if severity.priority != other.severity.priority {
            return severity.priority > other.severity.priority
        }

        if weight != other.weight {
            return weight > other.weight
        }

        return order < other.order
    }
}

private extension RuleSeverity {
    var priority: Int {
        switch self {
        case .info:
            return 0
        case .warn:
            return 1
        case .fail:
            return 2
        }
    }
}

public struct FormRuleEvaluator {
    public let ruleIDs: [String]

    private let compiledRules: [CompiledFormRule]
    private let minSignalConfidence: Double
    private var violationStartedAtMSByRuleID: [String: Int64] = [:]
    private var lastCueEmittedAtMSByRuleID: [String: Int64] = [:]
    private var extremeEpisodeStartedAtMSByRuleID: [String: Int64] = [:]
    private var extremeLatchedRuleIDs: Set<String> = []

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
            evaluateStateless(compiledRule, producedValues: producedValues, phase: phase, frame: frame)
        }
    }

    public mutating func update(
        timestampMS: Int64,
        producedValues: [String: SignalValue],
        phase: RepPhase,
        frame: PoseFrame? = nil
    ) -> [FormRuleSnapshot] {
        compiledRules.map { compiledRule in
            update(compiledRule, timestampMS: timestampMS, producedValues: producedValues, phase: phase, frame: frame)
        }
    }

    private func evaluateStateless(
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
                violationDurationMS: nil,
                cueCooldownRemainingMS: nil,
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
                violationDurationMS: nil,
                cueCooldownRemainingMS: nil,
                invalidReason: nil
            )
        case .unsatisfied:
            return FormRuleSnapshot(
                ruleID: rule.id,
                isActive: true,
                expectationPassed: false,
                cue: rule.cue,
                severity: rule.severity,
                violationDurationMS: nil,
                cueCooldownRemainingMS: nil,
                invalidReason: nil
            )
        case let .invalid(reason):
            return FormRuleSnapshot(
                ruleID: rule.id,
                isActive: true,
                expectationPassed: nil,
                cue: nil,
                severity: rule.severity,
                violationDurationMS: nil,
                cueCooldownRemainingMS: nil,
                invalidReason: reason
            )
        }
    }

    private mutating func update(
        _ compiledRule: CompiledFormRule,
        timestampMS: Int64,
        producedValues: [String: SignalValue],
        phase: RepPhase,
        frame: PoseFrame?
    ) -> FormRuleSnapshot {
        if compiledRule.rule.evaluation == .extreme {
            return updateExtreme(
                compiledRule,
                timestampMS: timestampMS,
                producedValues: producedValues,
                phase: phase,
                frame: frame
            )
        }

        let rule = compiledRule.rule
        let isActive = compiledRule.condition.matches(phase)

        guard isActive else {
            violationStartedAtMSByRuleID.removeValue(forKey: rule.id)
            return FormRuleSnapshot(
                ruleID: rule.id,
                isActive: false,
                expectationPassed: nil,
                cue: nil,
                severity: rule.severity,
                violationDurationMS: nil,
                cueCooldownRemainingMS: nil,
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
            violationStartedAtMSByRuleID.removeValue(forKey: rule.id)
            return FormRuleSnapshot(
                ruleID: rule.id,
                isActive: true,
                expectationPassed: true,
                cue: nil,
                severity: rule.severity,
                violationDurationMS: nil,
                cueCooldownRemainingMS: nil,
                invalidReason: nil
            )
        case .unsatisfied:
            let startedAtMS = violationStartedAtMSByRuleID[rule.id] ?? timestampMS
            violationStartedAtMSByRuleID[rule.id] = startedAtMS
            let durationMS = Int(max(0, timestampMS - startedAtMS))
            let cooldownRemainingBeforeCue = cueCooldownRemaining(for: rule, at: timestampMS)
            let shouldCue = durationMS >= rule.minViolationMS && cooldownRemainingBeforeCue == 0
            if shouldCue {
                lastCueEmittedAtMSByRuleID[rule.id] = timestampMS
            }
            let cueCooldownRemainingMS = shouldCue
                ? rule.cooldownMS
                : (cooldownRemainingBeforeCue > 0 ? cooldownRemainingBeforeCue : nil)

            return FormRuleSnapshot(
                ruleID: rule.id,
                isActive: true,
                expectationPassed: false,
                cue: shouldCue ? rule.cue : nil,
                severity: rule.severity,
                violationDurationMS: durationMS,
                cueCooldownRemainingMS: cueCooldownRemainingMS,
                invalidReason: nil
            )
        case let .invalid(reason):
            violationStartedAtMSByRuleID.removeValue(forKey: rule.id)
            return FormRuleSnapshot(
                ruleID: rule.id,
                isActive: true,
                expectationPassed: nil,
                cue: nil,
                severity: rule.severity,
                violationDurationMS: nil,
                cueCooldownRemainingMS: nil,
                invalidReason: reason
            )
        }
    }

    /// Episode-extreme evaluation: the expectation passes if it was satisfied at
    /// any frame while the rule's `when` condition held (e.g. "reached depth at
    /// the deepest point of the bottom"). While the episode runs, frames report
    /// pending (`expectationPassed == nil`) until the expectation latches true.
    /// One verdict snapshot is emitted on the frame where the episode ends; a
    /// failed episode shorter than `min_violation_ms` is discarded as a bounce.
    private mutating func updateExtreme(
        _ compiledRule: CompiledFormRule,
        timestampMS: Int64,
        producedValues: [String: SignalValue],
        phase: RepPhase,
        frame: PoseFrame?
    ) -> FormRuleSnapshot {
        let rule = compiledRule.rule
        let isActive = compiledRule.condition.matches(phase)

        guard isActive else {
            guard let startedAtMS = extremeEpisodeStartedAtMSByRuleID.removeValue(forKey: rule.id) else {
                return Self.inactiveSnapshot(for: rule)
            }

            let latched = extremeLatchedRuleIDs.remove(rule.id) != nil
            let episodeMS = Int(max(0, timestampMS - startedAtMS))

            if latched {
                return FormRuleSnapshot(
                    ruleID: rule.id,
                    isActive: true,
                    expectationPassed: true,
                    cue: nil,
                    severity: rule.severity,
                    violationDurationMS: nil,
                    cueCooldownRemainingMS: nil,
                    invalidReason: nil
                )
            }

            guard episodeMS >= rule.minViolationMS else {
                return Self.inactiveSnapshot(for: rule)
            }

            let cooldownRemainingBeforeCue = cueCooldownRemaining(for: rule, at: timestampMS)
            let shouldCue = cooldownRemainingBeforeCue == 0
            if shouldCue {
                lastCueEmittedAtMSByRuleID[rule.id] = timestampMS
            }

            return FormRuleSnapshot(
                ruleID: rule.id,
                isActive: true,
                expectationPassed: false,
                cue: shouldCue ? rule.cue : nil,
                severity: rule.severity,
                violationDurationMS: episodeMS,
                cueCooldownRemainingMS: shouldCue
                    ? rule.cooldownMS
                    : (cooldownRemainingBeforeCue > 0 ? cooldownRemainingBeforeCue : nil),
                invalidReason: nil
            )
        }

        if extremeEpisodeStartedAtMSByRuleID[rule.id] == nil {
            extremeEpisodeStartedAtMSByRuleID[rule.id] = timestampMS
        }

        let result = evaluate(
            compiledRule.expectation,
            producedValues: producedValues,
            frame: frame ?? Self.emptyFrame
        )

        if result == .satisfied {
            extremeLatchedRuleIDs.insert(rule.id)
        }

        let latchedSoFar = extremeLatchedRuleIDs.contains(rule.id)
        if case let .invalid(reason) = result, !latchedSoFar {
            return FormRuleSnapshot(
                ruleID: rule.id,
                isActive: true,
                expectationPassed: nil,
                cue: nil,
                severity: rule.severity,
                violationDurationMS: nil,
                cueCooldownRemainingMS: nil,
                invalidReason: reason
            )
        }

        return FormRuleSnapshot(
            ruleID: rule.id,
            isActive: true,
            expectationPassed: latchedSoFar ? true : nil,
            cue: nil,
            severity: rule.severity,
            violationDurationMS: nil,
            cueCooldownRemainingMS: nil,
            invalidReason: nil
        )
    }

    private static func inactiveSnapshot(for rule: FormRule) -> FormRuleSnapshot {
        FormRuleSnapshot(
            ruleID: rule.id,
            isActive: false,
            expectationPassed: nil,
            cue: nil,
            severity: rule.severity,
            violationDurationMS: nil,
            cueCooldownRemainingMS: nil,
            invalidReason: nil
        )
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

    private func cueCooldownRemaining(for rule: FormRule, at timestampMS: Int64) -> Int {
        guard let lastCueAtMS = lastCueEmittedAtMSByRuleID[rule.id] else {
            return 0
        }

        let cooldownUntilMS = lastCueAtMS + Int64(rule.cooldownMS)
        return Int(max(0, cooldownUntilMS - timestampMS))
    }
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
