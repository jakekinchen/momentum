import Foundation

public enum RepPhase: String, Equatable {
    case seekingReady = "seeking_ready"
    case ready
    case descending
    case bottom
    case ascending
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
    private var phaseStartedAtMS: Int64?

    public init(program: ExerciseProgram) throws {
        guard let rep = program.rep else {
            throw ProgramLoadError.invalidStructure(field: "rep", reason: "rep state machine requires rep config")
        }

        self.init(rep: rep)
    }

    public init(rep: RepConfig) {
        self.rep = rep
    }

    public mutating func update(
        timestampMS: Int64,
        downPredicate: PredicateResult,
        upPredicate: PredicateResult
    ) -> RepStateSnapshot {
        if let invalidReason = invalidReason(downPredicate: downPredicate, upPredicate: upPredicate) {
            resetActiveDwellTimer()
            return snapshot(countedThisFrame: false, invalidReason: invalidReason)
        }

        let isDown = downPredicate == .satisfied
        let isUp = upPredicate == .satisfied
        var countedThisFrame = false

        switch phase {
        case .seekingReady:
            if isUp {
                transition(to: .ready, timestampMS: nil)
            }
        case .ready:
            if isDown {
                transition(to: .descending, timestampMS: timestampMS)
            }
        case .descending:
            if isDown {
                let startedAt = ensurePhaseStarted(at: timestampMS)
                if elapsed(from: startedAt, to: timestampMS) >= rep.downMinMS {
                    transition(to: .bottom, timestampMS: timestampMS)
                }
            } else {
                transition(to: .ready, timestampMS: nil)
            }
        case .bottom:
            if isUp {
                guard let startedAt = phaseStartedAtMS,
                      elapsed(from: startedAt, to: timestampMS) >= rep.bottomMinMS else {
                    transition(to: .ready, timestampMS: nil)
                    return snapshot(countedThisFrame: false, invalidReason: nil)
                }

                transition(to: .ascending, timestampMS: timestampMS)
            } else if isDown {
                _ = ensurePhaseStarted(at: timestampMS)
            }
        case .ascending:
            if isUp {
                let startedAt = ensurePhaseStarted(at: timestampMS)
                if elapsed(from: startedAt, to: timestampMS) >= rep.upMinMS {
                    repCount += 1
                    countedThisFrame = true
                    transition(to: .ready, timestampMS: nil)
                }
            } else if isDown {
                transition(to: .bottom, timestampMS: timestampMS)
            } else {
                transition(to: .bottom, timestampMS: timestampMS)
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

    private mutating func transition(to nextPhase: RepPhase, timestampMS: Int64?) {
        phase = nextPhase
        phaseStartedAtMS = timestampMS
    }

    private mutating func ensurePhaseStarted(at timestampMS: Int64) -> Int64 {
        if let phaseStartedAtMS {
            return phaseStartedAtMS
        }

        phaseStartedAtMS = timestampMS
        return timestampMS
    }

    private func elapsed(from start: Int64, to end: Int64) -> Int {
        Int(max(0, end - start))
    }

    private mutating func resetActiveDwellTimer() {
        switch phase {
        case .descending, .bottom, .ascending:
            phaseStartedAtMS = nil
        case .seekingReady, .ready:
            break
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
