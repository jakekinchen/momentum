import Foundation

public struct FilterPipeline {
    private let filters: [String: SignalFilter]
    private var states: [String: FilterRuntimeState] = [:]

    public init(program: ExerciseProgram) {
        filters = program.filters
    }

    public mutating func apply(rawSignals: [String: SignalValue], timestampMS: Int64) -> [String: SignalValue] {
        var outputs: [String: SignalValue] = [:]

        for name in filters.keys.sorted() {
            guard let filter = filters[name] else { continue }
            var state = states[name] ?? FilterRuntimeState()

            if filter.type == .median {
                state.pruneMedianSamples(timestampMS: timestampMS, windowMS: filter.windowMS ?? 0)
            }

            guard let source = rawSignals[filter.source] else {
                outputs[name] = .invalid(reason: "filter \(name) missing raw source \(filter.source)")
                states[name] = state
                continue
            }

            guard case let .valid(value, confidence) = source else {
                if case let .invalid(reason) = source {
                    outputs[name] = .invalid(reason: "filter \(name) source \(filter.source) invalid: \(reason)")
                }
                states[name] = state
                continue
            }

            switch filter.type {
            case .ema:
                outputs[name] = state.applyEMA(value: value, confidence: confidence, alpha: filter.alpha ?? 1)
            case .median:
                outputs[name] = state.applyMedian(value: value, confidence: confidence, timestampMS: timestampMS, windowMS: filter.windowMS ?? 0)
            }

            states[name] = state
        }

        return outputs
    }
}

private struct FilterRuntimeState {
    var emaValue: Double?
    var emaConfidence: Double?
    var medianSamples: [MedianSample] = []

    mutating func applyEMA(value: Double, confidence: Double, alpha: Double) -> SignalValue {
        let filteredValue: Double
        let filteredConfidence: Double

        if let previousValue = emaValue, let previousConfidence = emaConfidence {
            filteredValue = alpha * value + (1 - alpha) * previousValue
            filteredConfidence = alpha * confidence + (1 - alpha) * previousConfidence
        } else {
            filteredValue = value
            filteredConfidence = confidence
        }

        emaValue = filteredValue
        emaConfidence = filteredConfidence
        return .valid(filteredValue, confidence: filteredConfidence)
    }

    mutating func applyMedian(value: Double, confidence: Double, timestampMS: Int64, windowMS: Int) -> SignalValue {
        medianSamples.append(MedianSample(timestampMS: timestampMS, value: value, confidence: confidence))
        pruneMedianSamples(timestampMS: timestampMS, windowMS: windowMS)

        let sortedSamples = medianSamples.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.timestampMS < rhs.timestampMS
            }
            return lhs.value < rhs.value
        }

        guard !sortedSamples.isEmpty else {
            return .invalid(reason: "median filter has no samples")
        }

        let middle = sortedSamples.count / 2
        if sortedSamples.count.isMultiple(of: 2) {
            let lower = sortedSamples[middle - 1]
            let upper = sortedSamples[middle]
            return .valid((lower.value + upper.value) / 2, confidence: min(lower.confidence, upper.confidence))
        }

        let sample = sortedSamples[middle]
        return .valid(sample.value, confidence: sample.confidence)
    }

    mutating func pruneMedianSamples(timestampMS: Int64, windowMS: Int) {
        let cutoff = timestampMS - Int64(windowMS)
        medianSamples = medianSamples.filter { sample in
            sample.timestampMS >= cutoff && sample.timestampMS <= timestampMS
        }
    }
}

private struct MedianSample {
    let timestampMS: Int64
    let value: Double
    let confidence: Double
}
