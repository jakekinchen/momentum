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
    public let formSnapshots: [FormRuleSnapshot]
    public let formSummary: FormRuleScoreSummary

    public var description: String {
        [
            "timestamp_ms=\(timestampMS)",
            rep.description,
            "produced=[\(producedValues.map(\.description).joined(separator: ", "))]",
            "form=[\(formSnapshots.map(\.description).joined(separator: " | "))]",
            "summary=\(formSummary)"
        ].joined(separator: " ")
    }
}

public struct EngineTraceRecorder {
    private var processor: FrameSignalProcessor
    private let predicateEvaluator: RepPredicateEvaluator
    private var stateMachine: RepStateMachine
    private var formEvaluator: FormRuleEvaluator
    private let formSummarizer: FormRuleScoreSummarizer
    private let phaseSignalName: String
    private let selectedProducedValueKeys: [String]

    public init(program: ExerciseProgram) throws {
        guard let rep = program.rep else {
            throw ProgramLoadError.invalidStructure(field: "rep", reason: "engine trace recorder requires rep config")
        }

        processor = try FrameSignalProcessor(program: program)
        predicateEvaluator = try RepPredicateEvaluator(program: program)
        stateMachine = RepStateMachine(rep: rep)
        formEvaluator = try FormRuleEvaluator(program: program)
        formSummarizer = FormRuleScoreSummarizer(program: program)
        phaseSignalName = rep.phaseSignal
        selectedProducedValueKeys = Self.selectedProducedValueKeys(program: program, phaseSignalName: rep.phaseSignal)
    }

    public mutating func record(frames: [PoseFrame]) -> [EngineTraceFrame] {
        frames.map { record(frame: $0) }
    }

    public mutating func record(frame: PoseFrame) -> EngineTraceFrame {
        let producedValues = processor.process(frame: frame)
        let repSnapshot = stateMachine.update(
            timestampMS: frame.timestampMS,
            phaseSignal: producedValues[phaseSignalName],
            downPredicate: predicateEvaluator.evaluateDown(producedValues: producedValues, frame: frame),
            upPredicate: predicateEvaluator.evaluateUp(producedValues: producedValues, frame: frame)
        )
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
}
