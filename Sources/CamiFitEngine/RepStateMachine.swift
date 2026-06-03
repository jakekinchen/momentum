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
    public let romDegrees: Double?

    public var description: String {
        var parts = [
            "phase=\(phase.rawValue)",
            "reps=\(repCount)",
            "counted=\(countedThisFrame)"
        ]

        if let romDegrees {
            parts.append(String(format: "rom=%.1f", romDegrees))
        }

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
    private var romMinimum: Double?
    private var romMaximum: Double?

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
        phaseSignal: SignalValue?,
        downPredicate: PredicateResult,
        upPredicate: PredicateResult
    ) -> RepStateSnapshot {
        guard let phaseSignalValue = validPhaseSignalValue(phaseSignal) else {
            resetActiveDwellTimer()
            return snapshot(
                countedThisFrame: false,
                invalidReason: invalidPhaseSignalReason(phaseSignal)
            )
        }

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
                startROMTracking(with: phaseSignalValue)
                transition(to: .descending, timestampMS: timestampMS)
            }
        case .descending:
            updateROM(with: phaseSignalValue)
            if isDown {
                let startedAt = ensurePhaseStarted(at: timestampMS)
                if elapsed(from: startedAt, to: timestampMS) >= rep.downMinMS {
                    transition(to: .bottom, timestampMS: timestampMS)
                }
            } else {
                resetROMTracking()
                transition(to: .ready, timestampMS: nil)
            }
        case .bottom:
            updateROM(with: phaseSignalValue)
            if isUp {
                guard let startedAt = phaseStartedAtMS,
                      elapsed(from: startedAt, to: timestampMS) >= rep.bottomMinMS else {
                    resetROMTracking()
                    transition(to: .ready, timestampMS: nil)
                    return snapshot(countedThisFrame: false, invalidReason: nil)
                }

                transition(to: .ascending, timestampMS: timestampMS)
            } else if isDown {
                _ = ensurePhaseStarted(at: timestampMS)
            }
        case .ascending:
            updateROM(with: phaseSignalValue)
            if isUp {
                let startedAt = ensurePhaseStarted(at: timestampMS)
                if elapsed(from: startedAt, to: timestampMS) >= rep.upMinMS {
                    let completedROM = currentROMDegrees
                    if (completedROM ?? 0) >= rep.minROMDegrees {
                        repCount += 1
                        countedThisFrame = true
                    }
                    resetROMTracking()
                    transition(to: .ready, timestampMS: nil)
                    return snapshot(countedThisFrame: countedThisFrame, invalidReason: nil, romDegrees: completedROM)
                }
            } else if isDown {
                transition(to: .bottom, timestampMS: timestampMS)
            } else {
                transition(to: .bottom, timestampMS: timestampMS)
            }
        }

        return snapshot(countedThisFrame: countedThisFrame, invalidReason: nil)
    }

    private func validPhaseSignalValue(_ phaseSignal: SignalValue?) -> Double? {
        guard case let .valid(value, _) = phaseSignal, value.isFinite else {
            return nil
        }

        return value
    }

    private func invalidPhaseSignalReason(_ phaseSignal: SignalValue?) -> String {
        switch phaseSignal {
        case nil:
            return "missing phase signal \(rep.phaseSignal)"
        case let .invalid(reason):
            return "phase signal \(rep.phaseSignal) invalid: \(reason)"
        case let .valid(value, _):
            return "phase signal \(rep.phaseSignal) invalid: non-finite value \(value)"
        }
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

    private mutating func startROMTracking(with value: Double) {
        romMinimum = value
        romMaximum = value
    }

    private mutating func updateROM(with value: Double) {
        guard romMinimum != nil, romMaximum != nil else {
            return
        }

        romMinimum = min(romMinimum ?? value, value)
        romMaximum = max(romMaximum ?? value, value)
    }

    private mutating func resetROMTracking() {
        romMinimum = nil
        romMaximum = nil
    }

    private var currentROMDegrees: Double? {
        guard let romMinimum, let romMaximum else {
            return nil
        }

        return romMaximum - romMinimum
    }

    private func snapshot(countedThisFrame: Bool, invalidReason: String?, romDegrees: Double? = nil) -> RepStateSnapshot {
        RepStateSnapshot(
            phase: phase,
            repCount: repCount,
            countedThisFrame: countedThisFrame,
            invalidReason: invalidReason,
            romDegrees: romDegrees ?? currentROMDegrees
        )
    }
}
