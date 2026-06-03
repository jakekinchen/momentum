import Foundation

public enum RepPhase: String, Equatable {
    case seekingReady = "seeking_ready"
    case ready
    case down
}

public struct RepStateSnapshot: Equatable, CustomStringConvertible {
    public let phase: RepPhase
    public let repCount: Int
    public let countedThisFrame: Bool
    public let invalidReason: String?

    public var description: String {
        var parts = [
            "phase=\(phase.rawValue)",
            "reps=\(repCount)",
            "counted=\(countedThisFrame)"
        ]

        if let invalidReason {
            parts.append("invalid=\(invalidReason)")
        }

        return parts.joined(separator: " ")
    }
}

public struct RepStateMachine {
    private let rep: RepConfig
    private var phase: RepPhase = .seekingReady
    private var repCount = 0

    public init(program: ExerciseProgram) throws {
        guard let rep = program.rep else {
            throw ProgramLoadError.invalidStructure(field: "rep", reason: "rep state machine requires rep config")
        }

        self.init(rep: rep)
    }

    public init(rep: RepConfig) {
        self.rep = rep
    }

    public mutating func update(downPredicate: PredicateResult, upPredicate: PredicateResult) -> RepStateSnapshot {
        if let invalidReason = invalidReason(downPredicate: downPredicate, upPredicate: upPredicate) {
            return snapshot(countedThisFrame: false, invalidReason: invalidReason)
        }

        let isDown = downPredicate == .satisfied
        let isUp = upPredicate == .satisfied
        var countedThisFrame = false

        switch phase {
        case .seekingReady:
            if isUp {
                phase = .ready
            }
        case .ready:
            if isDown {
                phase = .down
            }
        case .down:
            if isUp {
                repCount += 1
                countedThisFrame = true
                phase = .ready
            }
        }

        return snapshot(countedThisFrame: countedThisFrame, invalidReason: nil)
    }

    private func invalidReason(downPredicate: PredicateResult, upPredicate: PredicateResult) -> String? {
        switch (downPredicate, upPredicate) {
        case let (.invalid(reason), _):
            return "down predicate invalid: \(reason)"
        case let (_, .invalid(reason)):
            return "up predicate invalid: \(reason)"
        default:
            return nil
        }
    }

    private func snapshot(countedThisFrame: Bool, invalidReason: String?) -> RepStateSnapshot {
        RepStateSnapshot(
            phase: phase,
            repCount: repCount,
            countedThisFrame: countedThisFrame,
            invalidReason: invalidReason
        )
    }
}
