import Foundation

public protocol ProgramStringEnum: Codable, CaseIterable, RawRepresentable where RawValue == String {}

public extension ProgramStringEnum {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        guard let parsed = Self(rawValue: value) else {
            throw ProgramLoadError.invalidEnumValue(
                field: decoder.codingPath.programPath,
                value: value,
                allowed: Self.allCases.map(\.rawValue).sorted()
            )
        }

        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ExerciseProgram: Codable, Equatable {
    public let schemaVersion: Int
    public let id: String
    public let name: String
    public let coordinateSpace: CoordinateSpace
    public let setup: ProgramSetup
    public let landmarkAliases: [String: String]
    public let signals: [String: String]
    public let filters: [String: SignalFilter]
    public let validity: ValidityConfig
    public let rep: RepConfig?
    public let hold: HoldConfig?
    public let formRules: [FormRule]
    public let set: SetConfig

    public init(
        schemaVersion: Int,
        id: String,
        name: String,
        coordinateSpace: CoordinateSpace,
        setup: ProgramSetup,
        landmarkAliases: [String: String],
        signals: [String: String],
        filters: [String: SignalFilter],
        validity: ValidityConfig,
        rep: RepConfig?,
        hold: HoldConfig?,
        formRules: [FormRule],
        set: SetConfig
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.coordinateSpace = coordinateSpace
        self.setup = setup
        self.landmarkAliases = landmarkAliases
        self.signals = signals
        self.filters = filters
        self.validity = validity
        self.rep = rep
        self.hold = hold
        self.formRules = formRules
        self.set = set
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case name
        case coordinateSpace = "coordinate_space"
        case setup
        case landmarkAliases = "landmark_aliases"
        case signals
        case filters
        case validity
        case rep
        case hold
        case formRules = "form_rules"
        case set
    }
}

public enum CoordinateSpace: String, ProgramStringEnum {
    case image2D = "image2d"
    case world
}

public struct ProgramSetup: Codable, Equatable {
    public let requiredView: RequiredView
    public let requiredLandmarks: [String]
    public let minVisibility: Double
    public let primarySide: PrimarySide
    public let mirrorHandling: MirrorHandling
    public let calibration: [String: CalibrationCapture]

    public init(
        requiredView: RequiredView,
        requiredLandmarks: [String],
        minVisibility: Double,
        primarySide: PrimarySide,
        mirrorHandling: MirrorHandling,
        calibration: [String: CalibrationCapture]
    ) {
        self.requiredView = requiredView
        self.requiredLandmarks = requiredLandmarks
        self.minVisibility = minVisibility
        self.primarySide = primarySide
        self.mirrorHandling = mirrorHandling
        self.calibration = calibration
    }

    private enum CodingKeys: String, CodingKey {
        case requiredView = "required_view"
        case requiredLandmarks = "required_landmarks"
        case minVisibility = "min_visibility"
        case primarySide = "primary_side"
        case mirrorHandling = "mirror_handling"
        case calibration
    }
}

public enum RequiredView: String, ProgramStringEnum {
    case front
    case side
}

public enum PrimarySide: String, ProgramStringEnum {
    case autoLock = "auto_lock"
    case left
    case right
}

public enum MirrorHandling: String, ProgramStringEnum {
    case detect
    case mirrored
    case unmirrored
}

public struct CalibrationCapture: Codable, Equatable {
    public let instruction: String
    public let captureSeconds: Double
    public let signals: [String]

    public init(instruction: String, captureSeconds: Double, signals: [String]) {
        self.instruction = instruction
        self.captureSeconds = captureSeconds
        self.signals = signals
    }

    private enum CodingKeys: String, CodingKey {
        case instruction
        case captureSeconds = "capture_seconds"
        case signals
    }
}

public struct SignalFilter: Codable, Equatable {
    public let source: String
    public let type: FilterType
    public let alpha: Double?
    public let windowMS: Int?

    public init(source: String, type: FilterType, alpha: Double? = nil, windowMS: Int? = nil) {
        self.source = source
        self.type = type
        self.alpha = alpha
        self.windowMS = windowMS
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case type
        case alpha
        case windowMS = "window_ms"
    }
}

public enum FilterType: String, ProgramStringEnum {
    case ema
    case median
}

public struct ValidityConfig: Codable, Equatable {
    public let minSignalConfidence: Double
    public let phaseSignalInvalidPolicy: PhaseSignalInvalidPolicy
    public let freezeMS: Int
    public let resetAfterMS: Int

    public init(
        minSignalConfidence: Double,
        phaseSignalInvalidPolicy: PhaseSignalInvalidPolicy,
        freezeMS: Int,
        resetAfterMS: Int
    ) {
        self.minSignalConfidence = minSignalConfidence
        self.phaseSignalInvalidPolicy = phaseSignalInvalidPolicy
        self.freezeMS = freezeMS
        self.resetAfterMS = resetAfterMS
    }

    private enum CodingKeys: String, CodingKey {
        case minSignalConfidence = "min_signal_confidence"
        case phaseSignalInvalidPolicy = "phase_signal_invalid_policy"
        case freezeMS = "freeze_ms"
        case resetAfterMS = "reset_after_ms"
    }
}

public enum PhaseSignalInvalidPolicy: String, ProgramStringEnum {
    case freezeThenReset = "freeze_then_reset"
}

public struct RepConfig: Codable, Equatable {
    public let phaseSignal: String
    public let downWhen: String
    public let downMinMS: Int
    public let bottomMinMS: Int
    public let upWhen: String
    public let upMinMS: Int
    public let minROMDegrees: Double
    public let cooldownMS: Int

    public init(
        phaseSignal: String,
        downWhen: String,
        downMinMS: Int,
        bottomMinMS: Int,
        upWhen: String,
        upMinMS: Int,
        minROMDegrees: Double,
        cooldownMS: Int
    ) {
        self.phaseSignal = phaseSignal
        self.downWhen = downWhen
        self.downMinMS = downMinMS
        self.bottomMinMS = bottomMinMS
        self.upWhen = upWhen
        self.upMinMS = upMinMS
        self.minROMDegrees = minROMDegrees
        self.cooldownMS = cooldownMS
    }

    private enum CodingKeys: String, CodingKey {
        case phaseSignal = "phase_signal"
        case downWhen = "down_when"
        case downMinMS = "down_min_ms"
        case bottomMinMS = "bottom_min_ms"
        case upWhen = "up_when"
        case upMinMS = "up_min_ms"
        case minROMDegrees = "min_rom_deg"
        case cooldownMS = "cooldown_ms"
    }
}

public struct HoldConfig: Codable, Equatable {
    public let signal: String
    public let inRange: String
    public let targetSeconds: Double

    public init(signal: String, inRange: String, targetSeconds: Double) {
        self.signal = signal
        self.inRange = inRange
        self.targetSeconds = targetSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case signal
        case inRange = "in_range"
        case targetSeconds = "target_seconds"
    }
}

/// How a form rule's expectation is judged while its `when` condition is active.
///
/// `instant` evaluates every frame — right for "maintain" expectations (keep the
/// torso tall, keep symmetry). `extreme` judges reach expectations ("get the knee
/// to depth", "finish the extension") once per active episode: the expectation
/// passes if it was satisfied at any frame of the episode, and a single verdict
/// is emitted when the episode ends. Instant evaluation of reach expectations is
/// structurally wrong because the `bottom` phase spans the ascent back to the up
/// gate, so every rep would violate while standing back up.
public enum FormRuleEvaluation: String, ProgramStringEnum {
    case instant
    case extreme
}

public struct FormRule: Codable, Equatable {
    public let id: String
    public let when: String
    public let expect: String
    public let minViolationMS: Int
    public let cue: String
    public let severity: RuleSeverity
    public let scoreWeight: Double
    public let cooldownMS: Int
    public let evaluation: FormRuleEvaluation

    public init(
        id: String,
        when: String,
        expect: String,
        minViolationMS: Int,
        cue: String,
        severity: RuleSeverity,
        scoreWeight: Double,
        cooldownMS: Int,
        evaluation: FormRuleEvaluation = .instant
    ) {
        self.id = id
        self.when = when
        self.expect = expect
        self.minViolationMS = minViolationMS
        self.cue = cue
        self.severity = severity
        self.scoreWeight = scoreWeight
        self.cooldownMS = cooldownMS
        self.evaluation = evaluation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        when = try container.decode(String.self, forKey: .when)
        expect = try container.decode(String.self, forKey: .expect)
        minViolationMS = try container.decode(Int.self, forKey: .minViolationMS)
        cue = try container.decode(String.self, forKey: .cue)
        severity = try container.decode(RuleSeverity.self, forKey: .severity)
        scoreWeight = try container.decode(Double.self, forKey: .scoreWeight)
        cooldownMS = try container.decode(Int.self, forKey: .cooldownMS)
        evaluation = try container.decodeIfPresent(FormRuleEvaluation.self, forKey: .evaluation) ?? .instant
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case when
        case expect
        case minViolationMS = "min_violation_ms"
        case cue
        case severity
        case scoreWeight = "score_weight"
        case cooldownMS = "cooldown_ms"
        case evaluation
    }
}

public enum RuleSeverity: String, ProgramStringEnum {
    case info
    case warn
    case fail
}

public struct SetConfig: Codable, Equatable {
    public let targetReps: Int?
    public let targetSeconds: Double?

    public init(targetReps: Int? = nil, targetSeconds: Double? = nil) {
        self.targetReps = targetReps
        self.targetSeconds = targetSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case targetReps = "target_reps"
        case targetSeconds = "target_seconds"
    }
}

public extension ExerciseProgram {
    var validatedSummary: String {
        let repSummary = rep.map { "rep_phase=\($0.phaseSignal),down=\($0.downWhen),up=\($0.upWhen)" } ?? "rep_phase=nil"
        let holdSummary = hold.map { "hold_signal=\($0.signal),target_seconds=\($0.targetSeconds)" } ?? "hold_signal=nil"

        return [
            "id=\(id)",
            "signals=\(signals.keys.sorted().joined(separator: ","))",
            "filters=\(filters.keys.sorted().joined(separator: ","))",
            repSummary,
            holdSummary,
            "form_rules=\(formRules.map(\.id).joined(separator: ","))"
        ].joined(separator: " ")
    }
}
