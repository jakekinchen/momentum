import Foundation

public struct EngineTraceProducedValue: Equatable, CustomStringConvertible {
    public let key: String
    public let value: SignalValue

    public var description: String {
        "\(key)=\(value)"
    }
}

public struct EngineTraceFrame: Equatable, CustomStringConvertible {
    public let timestampMS: Int64
    public let producedValues: [EngineTraceProducedValue]
    public let rep: RepStateSnapshot
    public let hold: HoldSnapshot?
    public let formSnapshots: [FormRuleSnapshot]
    public let formSummary: FormRuleScoreSummary

    public var description: String {
        var parts = [
            "timestamp_ms=\(timestampMS)",
            rep.description,
            "produced=[\(producedValues.map(\.description).joined(separator: ", "))]"
        ]

        if let hold {
            parts.append(hold.description)
        }

        parts.append("form=[\(formSnapshots.map(\.description).joined(separator: " | "))]")
        parts.append("summary=\(formSummary)")
        return parts.joined(separator: " ")
    }
}

public struct EngineTraceRecorder {
    private var processor: FrameSignalProcessor
    private let predicateEvaluator: RepPredicateEvaluator?
    private var stateMachine: RepStateMachine?
    private var holdEvaluator: HoldEvaluator?
    private var formEvaluator: FormRuleEvaluator
    private let formSummarizer: FormRuleScoreSummarizer
    private let phaseSignalName: String
    private let selectedProducedValueKeys: [String]

    public init(program: ExerciseProgram) throws {
        processor = try FrameSignalProcessor(program: program)
        formEvaluator = try FormRuleEvaluator(program: program)
        formSummarizer = FormRuleScoreSummarizer(program: program)

        if let rep = program.rep {
            predicateEvaluator = try RepPredicateEvaluator(program: program)
            stateMachine = RepStateMachine(rep: rep)
            holdEvaluator = nil
            phaseSignalName = rep.phaseSignal
        } else if let hold = program.hold {
            predicateEvaluator = nil
            stateMachine = nil
            holdEvaluator = try HoldEvaluator(program: program)
            phaseSignalName = hold.signal
        } else {
            throw ProgramLoadError.invalidStructure(field: "program", reason: "engine trace recorder requires rep or hold config")
        }

        selectedProducedValueKeys = Self.selectedProducedValueKeys(program: program, phaseSignalName: phaseSignalName)
    }

    public mutating func record(frames: [PoseFrame]) -> [EngineTraceFrame] {
        frames.map { record(frame: $0) }
    }

    public mutating func record(frame: PoseFrame) -> EngineTraceFrame {
        let producedValues = processor.process(frame: frame)
        let repSnapshot: RepStateSnapshot
        if let predicateEvaluator, var stateMachine {
            repSnapshot = stateMachine.update(
                timestampMS: frame.timestampMS,
                phaseSignal: producedValues[phaseSignalName],
                downPredicate: predicateEvaluator.evaluateDown(producedValues: producedValues, frame: frame),
                upPredicate: predicateEvaluator.evaluateUp(producedValues: producedValues, frame: frame)
            )
            self.stateMachine = stateMachine
        } else {
            repSnapshot = Self.noRepSnapshot
        }

        let holdSnapshot: HoldSnapshot?
        if var holdEvaluator {
            holdSnapshot = holdEvaluator.update(timestampMS: frame.timestampMS, producedValues: producedValues, frame: frame)
            self.holdEvaluator = holdEvaluator
        } else {
            holdSnapshot = nil
        }

        let formSnapshots = formEvaluator.update(
            timestampMS: frame.timestampMS,
            producedValues: producedValues,
            phase: repSnapshot.phase,
            frame: frame
        )

        return EngineTraceFrame(
            timestampMS: frame.timestampMS,
            producedValues: traceProducedValues(from: producedValues),
            rep: repSnapshot,
            hold: holdSnapshot,
            formSnapshots: formSnapshots,
            formSummary: formSummarizer.summarize(formSnapshots)
        )
    }

    private func traceProducedValues(from producedValues: [String: SignalValue]) -> [EngineTraceProducedValue] {
        selectedProducedValueKeys.compactMap { key in
            guard let value = producedValues[key] else {
                return nil
            }

            return EngineTraceProducedValue(key: key, value: value)
        }
    }

    private static func selectedProducedValueKeys(program: ExerciseProgram, phaseSignalName: String) -> [String] {
        var keys = Set<String>()
        keys.insert(phaseSignalName)
        keys.insert("knee")
        keys.insert("torso_tilt")
        keys.insert("knee_symmetry")

        let producedKeys = Set(program.signals.keys).union(program.filters.keys)
        return keys.intersection(producedKeys).sorted()
    }

    private static let noRepSnapshot = RepStateSnapshot(
        phase: .ready,
        repCount: 0,
        countedThisFrame: false,
        invalidReason: nil,
        romDegrees: nil,
        cooldownRemainingMS: nil
    )
}

public enum EngineTraceFormatter {
    public static func format(_ trace: [EngineTraceFrame]) -> String {
        let includesHold = trace.contains { $0.hold != nil }
        let header = includesHold
            ? "timestamp_ms | phase | reps | counted | produced | hold | form | cue | score | invalid"
            : "timestamp_ms | phase | reps | counted | produced | form | cue | score | invalid"

        return ([header] + trace.map { format(frame: $0, includesHold: includesHold) }).joined(separator: "\n")
    }

    private static func format(frame: EngineTraceFrame, includesHold: Bool) -> String {
        var parts = [
            String(frame.timestampMS),
            frame.rep.phase.rawValue,
            String(frame.rep.repCount),
            String(frame.rep.countedThisFrame),
            producedDescription(frame.producedValues)
        ]

        if includesHold {
            parts.append(holdDescription(frame.hold))
        }

        parts.append(contentsOf: [
            formDescription(frame.formSnapshots),
            cueDescription(frame.formSummary),
            scoreDescription(frame.formSummary),
            invalidDescription(frame.rep.invalidReason)
        ])

        return parts.joined(separator: " | ")
    }

    private static func producedDescription(_ producedValues: [EngineTraceProducedValue]) -> String {
        guard !producedValues.isEmpty else {
            return "produced=none"
        }

        return producedValues.map(\.description).joined(separator: ",")
    }

    private static func holdDescription(_ hold: HoldSnapshot?) -> String {
        guard let hold else {
            return "hold=nil"
        }

        let reason = hold.notAccumulatingReason ?? "nil"
        return String(
            format: "held=%.3f,in_range=%@,valid=%@,target=%@,reason=%@",
            hold.heldSeconds,
            String(hold.inRange),
            String(hold.valid),
            String(hold.targetReached),
            reason
        )
    }

    private static func formDescription(_ snapshots: [FormRuleSnapshot]) -> String {
        let active = snapshots.filter(\.isActive)
        guard !active.isEmpty else {
            return "form=none"
        }

        return active.map { snapshot in
            "\(snapshot.ruleID):\(expectationDescription(snapshot.expectationPassed))"
        }.joined(separator: ",")
    }

    private static func expectationDescription(_ expectationPassed: Bool?) -> String {
        switch expectationPassed {
        case .some(true):
            return "pass"
        case .some(false):
            return "fail"
        case .none:
            return "invalid"
        }
    }

    private static func cueDescription(_ summary: FormRuleScoreSummary) -> String {
        guard let selectedCueRuleID = summary.selectedCueRuleID,
              let selectedCue = summary.selectedCue else {
            return "cue=nil"
        }

        return "cue=\(selectedCueRuleID):\(selectedCue)"
    }

    private static func scoreDescription(_ summary: FormRuleScoreSummary) -> String {
        let score = summary.score.map { String(format: "%.3f", $0) } ?? "nil"
        return "score=\(score)"
    }

    private static func invalidDescription(_ invalidReason: String?) -> String {
        "invalid=\(invalidReason ?? "nil")"
    }
}
