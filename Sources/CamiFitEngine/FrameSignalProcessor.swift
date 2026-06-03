import Foundation

public struct FrameSignalProcessor {
    private let signalEvaluator: SignalEvaluator
    private var filterPipeline: FilterPipeline

    public init(program: ExerciseProgram) throws {
        signalEvaluator = try SignalEvaluator(program: program)
        filterPipeline = FilterPipeline(program: program)
    }

    public mutating func process(frame: PoseFrame) -> [String: SignalValue] {
        let rawSignals = signalEvaluator.evaluateSignals(frame: frame)
        let filteredSignals = filterPipeline.apply(rawSignals: rawSignals, timestampMS: frame.timestampMS)

        return rawSignals.merging(filteredSignals) { _, filtered in
            filtered
        }
    }
}
