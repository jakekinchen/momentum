import Foundation

public enum ProgramLoadError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case missingRequiredField(field: String)
    case invalidEnumValue(field: String, value: String, allowed: [String])
    case missingReference(field: String, name: String)
    case invalidCalibrationSignalReference(field: String, name: String)
    case unknownFunction(field: String, name: String, allowed: [String])
    case cyclicSignalReference(name: String)
    case invalidStructure(field: String, reason: String)
    case fileReadFailed(path: String, reason: String)
    case decodingFailed(field: String, reason: String)

    public var description: String {
        switch self {
        case let .missingRequiredField(field):
            return "missing_required_field(field: \(field))"
        case let .invalidEnumValue(field, value, allowed):
            return "invalid_enum_value(field: \(field), value: \(value), allowed: \(allowed.joined(separator: ",")))"
        case let .missingReference(field, name):
            return "missing_reference(field: \(field), name: \(name))"
        case let .invalidCalibrationSignalReference(field, name):
            return "invalid_calibration_signal_reference(field: \(field), name: \(name))"
        case let .unknownFunction(field, name, allowed):
            return "unknown_function(field: \(field), name: \(name), allowed: \(allowed.joined(separator: ",")))"
        case let .cyclicSignalReference(name):
            return "cyclic_signal_reference(name: \(name))"
        case let .invalidStructure(field, reason):
            return "invalid_structure(field: \(field), reason: \(reason))"
        case let .fileReadFailed(path, reason):
            return "file_read_failed(path: \(path), reason: \(reason))"
        case let .decodingFailed(field, reason):
            return "decoding_failed(field: \(field), reason: \(reason))"
        }
    }

    public var errorDescription: String? {
        description
    }
}

public enum ProgramLoader {
    public static func load(from url: URL) throws -> ExerciseProgram {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ProgramLoadError.fileReadFailed(path: url.path, reason: String(describing: error))
        }

        return try load(data: data)
    }

    public static func loadPreset(named presetName: String, in directory: URL? = nil) throws -> ExerciseProgram {
        let presetDirectory = directory ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Presets", isDirectory: true)
        let url = presetDirectory.appendingPathComponent("\(presetName).json")
        return try load(from: url)
    }

    public static func load(data: Data) throws -> ExerciseProgram {
        let decoder = JSONDecoder()

        do {
            let program = try decoder.decode(ExerciseProgram.self, from: data)
            try ProgramValidator.validate(program)
            return program
        } catch let error as ProgramLoadError {
            throw error
        } catch let error as DecodingError {
            throw ProgramLoadError.from(decodingError: error)
        } catch {
            throw ProgramLoadError.decodingFailed(field: "program", reason: String(describing: error))
        }
    }
}

private enum ProgramValidator {
    static func validate(_ program: ExerciseProgram) throws {
        try require(program.schemaVersion == 1, field: "schemaVersion", reason: "only schemaVersion 1 is supported")
        try require(!program.id.isEmpty, field: "id", reason: "must not be empty")
        try require(!program.name.isEmpty, field: "name", reason: "must not be empty")
        try validateSetup(program.setup, aliases: program.landmarkAliases)

        let signalNames = Set(program.signals.keys)
        let filterNames = Set(program.filters.keys)
        try require(!signalNames.isEmpty, field: "signals", reason: "at least one signal is required")

        let duplicatePublishedNames = signalNames.intersection(filterNames)
        if let duplicate = duplicatePublishedNames.sorted().first {
            throw ProgramLoadError.invalidStructure(
                field: "filters.\(duplicate)",
                reason: "filter output duplicates a raw signal name"
            )
        }

        let aliasNames = Set(program.landmarkAliases.keys)
        for alias in aliasNames.sorted() {
            let reference = program.landmarkAliases[alias] ?? ""
            try require(
                ExpressionReferenceScanner.isLandmarkReference(reference),
                field: "landmark_aliases.\(alias)",
                reason: "must map to a left/right/primary landmark reference"
            )
        }

        var signalDependencies: [String: Set<String>] = [:]
        for name in signalNames.sorted() {
            let expression = program.signals[name] ?? ""
            let references = try ExpressionReferenceScanner.validate(
                expression,
                field: "signals.\(name)",
                knownValues: signalNames,
                aliases: aliasNames,
                allowState: false
            )
            signalDependencies[name] = references.filter { signalNames.contains($0) }
        }
        try validateSignalGraph(signalDependencies)

        for name in filterNames.sorted() {
            guard let filter = program.filters[name] else { continue }
            guard signalNames.contains(filter.source) else {
                throw ProgramLoadError.missingReference(field: "filters.\(name).source", name: filter.source)
            }
            try validateFilter(filter, name: name)
        }

        let producedValues = signalNames.union(filterNames)
        try validateCalibrationSignals(program.setup, producedValues: producedValues)

        if program.rep == nil && program.hold == nil {
            throw ProgramLoadError.invalidStructure(field: "program", reason: "either rep or hold must be provided")
        }

        if program.rep != nil && program.hold != nil {
            throw ProgramLoadError.invalidStructure(field: "program", reason: "rep and hold are mutually exclusive")
        }

        if let rep = program.rep {
            guard producedValues.contains(rep.phaseSignal) else {
                throw ProgramLoadError.missingReference(field: "rep.phase_signal", name: rep.phaseSignal)
            }

            _ = try ExpressionReferenceScanner.validate(
                rep.downWhen,
                field: "rep.down_when",
                knownValues: producedValues,
                aliases: aliasNames,
                allowState: true
            )
            _ = try ExpressionReferenceScanner.validate(
                rep.upWhen,
                field: "rep.up_when",
                knownValues: producedValues,
                aliases: aliasNames,
                allowState: true
            )
            try require(rep.downMinMS >= 0, field: "rep.down_min_ms", reason: "must be non-negative")
            try require(rep.bottomMinMS >= 0, field: "rep.bottom_min_ms", reason: "must be non-negative")
            try require(rep.upMinMS >= 0, field: "rep.up_min_ms", reason: "must be non-negative")
            try require(rep.minROMDegrees > 0, field: "rep.min_rom_deg", reason: "must be positive")
            try require(rep.cooldownMS >= 0, field: "rep.cooldown_ms", reason: "must be non-negative")
        }

        if let hold = program.hold {
            guard producedValues.contains(hold.signal) else {
                throw ProgramLoadError.missingReference(field: "hold.signal", name: hold.signal)
            }
            _ = try ExpressionReferenceScanner.validate(
                hold.inRange,
                field: "hold.in_range",
                knownValues: producedValues,
                aliases: aliasNames,
                allowState: true
            )
            try require(hold.targetSeconds > 0, field: "hold.target_seconds", reason: "must be positive")
        }

        for (index, rule) in program.formRules.enumerated() {
            try require(!rule.id.isEmpty, field: "form_rules[\(index)].id", reason: "must not be empty")
            _ = try ExpressionReferenceScanner.validate(
                rule.when,
                field: "form_rules[\(index)].when",
                knownValues: producedValues,
                aliases: aliasNames,
                allowState: true
            )
            _ = try ExpressionReferenceScanner.validate(
                rule.expect,
                field: "form_rules[\(index)].expect",
                knownValues: producedValues,
                aliases: aliasNames,
                allowState: true
            )
            try require(rule.minViolationMS >= 0, field: "form_rules[\(index)].min_violation_ms", reason: "must be non-negative")
            try require(rule.scoreWeight >= 0, field: "form_rules[\(index)].score_weight", reason: "must be non-negative")
            try require(rule.cooldownMS >= 0, field: "form_rules[\(index)].cooldown_ms", reason: "must be non-negative")
        }

        switch (program.set.targetReps, program.set.targetSeconds) {
        case (.some(let reps), nil):
            try require(reps > 0, field: "set.target_reps", reason: "must be positive")
        case (nil, .some(let seconds)):
            try require(seconds > 0, field: "set.target_seconds", reason: "must be positive")
        case (nil, nil):
            throw ProgramLoadError.missingRequiredField(field: "set.target_reps")
        case (.some, .some):
            throw ProgramLoadError.invalidStructure(field: "set", reason: "target_reps and target_seconds are mutually exclusive")
        }
    }

    private static func validateSetup(_ setup: ProgramSetup, aliases: [String: String]) throws {
        try require(!setup.requiredLandmarks.isEmpty, field: "setup.required_landmarks", reason: "at least one landmark is required")
        try require((0 ... 1).contains(setup.minVisibility), field: "setup.min_visibility", reason: "must be between 0 and 1")

        for (index, landmark) in setup.requiredLandmarks.enumerated() {
            try require(
                ExpressionReferenceScanner.isLandmarkReference(landmark) || aliases[landmark] != nil,
                field: "setup.required_landmarks[\(index)]",
                reason: "must be a known landmark reference or alias"
            )
        }

        for key in setup.calibration.keys.sorted() {
            guard let capture = setup.calibration[key] else { continue }
            try require(!capture.instruction.isEmpty, field: "setup.calibration.\(key).instruction", reason: "must not be empty")
            try require(capture.captureSeconds > 0, field: "setup.calibration.\(key).capture_seconds", reason: "must be positive")
        }
    }

    private static func validateFilter(_ filter: SignalFilter, name: String) throws {
        switch filter.type {
        case .ema:
            guard let alpha = filter.alpha else {
                throw ProgramLoadError.missingRequiredField(field: "filters.\(name).alpha")
            }
            try require((0 ... 1).contains(alpha), field: "filters.\(name).alpha", reason: "must be between 0 and 1")
        case .median:
            guard let windowMS = filter.windowMS else {
                throw ProgramLoadError.missingRequiredField(field: "filters.\(name).window_ms")
            }
            try require(windowMS > 0, field: "filters.\(name).window_ms", reason: "must be positive")
        }
    }

    private static func validateCalibrationSignals(_ setup: ProgramSetup, producedValues: Set<String>) throws {
        for calibrationName in setup.calibration.keys.sorted() {
            guard let capture = setup.calibration[calibrationName] else { continue }

            for (index, signalName) in capture.signals.enumerated() {
                guard producedValues.contains(signalName) else {
                    throw ProgramLoadError.invalidCalibrationSignalReference(
                        field: "setup.calibration.\(calibrationName).signals[\(index)]",
                        name: signalName
                    )
                }
            }
        }
    }

    private static func validateSignalGraph(_ dependencies: [String: Set<String>]) throws {
        enum VisitState {
            case visiting
            case visited
        }

        var states: [String: VisitState] = [:]

        func visit(_ name: String, stack: [String]) throws {
            if states[name] == .visited {
                return
            }

            if states[name] == .visiting {
                throw ProgramLoadError.cyclicSignalReference(name: name)
            }

            states[name] = .visiting
            for dependency in (dependencies[name] ?? []).sorted() {
                try visit(dependency, stack: stack + [name])
            }
            states[name] = .visited
        }

        for name in dependencies.keys.sorted() {
            try visit(name, stack: [])
        }
    }

    private static func require(_ condition: Bool, field: String, reason: String) throws {
        if !condition {
            throw ProgramLoadError.invalidStructure(field: field, reason: reason)
        }
    }
}

private enum ExpressionReferenceScanner {
    private static let identifierPattern = #"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?"#
    private static let identifierRegex = try! NSRegularExpression(pattern: identifierPattern)

    private static let keywords: Set<String> = [
        "and",
        "between",
        "false",
        "in",
        "not",
        "null",
        "or",
        "true"
    ]

    private static let stateVariables: Set<String> = [
        "phase",
        "rep_count",
        "time_in_phase_ms"
    ]

    private static let landmarkPrefixes: Set<String> = [
        "left",
        "primary",
        "right"
    ]

    private static let landmarkNames: Set<String> = [
        "ankle",
        "ear",
        "elbow",
        "eye",
        "foot_index",
        "heel",
        "hip",
        "index",
        "knee",
        "mouth",
        "nose",
        "pinky",
        "shoulder",
        "thumb",
        "wrist"
    ]

    private static let allowedFunctions: Set<String> = [
        "abs",
        "angle",
        "angle_to_horizontal",
        "angle_to_vertical",
        "distance",
        "max",
        "midpoint",
        "min",
        "ratio",
        "signed_angle"
    ]

    static func validate(
        _ expression: String,
        field: String,
        knownValues: Set<String>,
        aliases: Set<String>,
        allowState: Bool
    ) throws -> Set<String> {
        let sanitized = stripStringLiterals(from: expression)
        let source = sanitized as NSString
        let matches = identifierRegex.matches(
            in: sanitized,
            range: NSRange(location: 0, length: source.length)
        )

        var references = Set<String>()

        for match in matches {
            let token = source.substring(with: match.range)

            if isFunctionCall(after: match.range, in: source) {
                guard allowedFunctions.contains(token) else {
                    throw ProgramLoadError.unknownFunction(
                        field: field,
                        name: token,
                        allowed: allowedFunctions.sorted()
                    )
                }
                continue
            }

            if keywords.contains(token) {
                continue
            }

            if token.contains(".") {
                guard isLandmarkReference(token) else {
                    throw ProgramLoadError.missingReference(field: field, name: token)
                }
                continue
            }

            if allowState && stateVariables.contains(token) {
                continue
            }

            if aliases.contains(token) {
                continue
            }

            if knownValues.contains(token) {
                references.insert(token)
                continue
            }

            throw ProgramLoadError.missingReference(field: field, name: token)
        }

        return references
    }

    static func isLandmarkReference(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return false
        }

        return landmarkPrefixes.contains(String(parts[0])) && landmarkNames.contains(String(parts[1]))
    }

    private static func stripStringLiterals(from expression: String) -> String {
        var result = ""
        var quote: Character?
        var escaped = false

        for character in expression {
            if let activeQuote = quote {
                result.append(" ")
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == activeQuote {
                    quote = nil
                }
            } else if character == "'" || character == "\"" {
                quote = character
                result.append(" ")
            } else {
                result.append(character)
            }
        }

        return result
    }

    private static func isFunctionCall(after range: NSRange, in source: NSString) -> Bool {
        var index = range.location + range.length

        while index < source.length {
            guard let scalar = UnicodeScalar(source.character(at: index)),
                  CharacterSet.whitespacesAndNewlines.contains(scalar) else {
                break
            }
            index += 1
        }

        guard index < source.length else {
            return false
        }

        return source.character(at: index) == Character("(").utf16.first
    }
}

private extension ProgramLoadError {
    static func from(decodingError: DecodingError) -> ProgramLoadError {
        switch decodingError {
        case let .keyNotFound(key, context):
            return .missingRequiredField(field: (context.codingPath + [key]).programPath)
        case let .valueNotFound(_, context):
            return .missingRequiredField(field: context.codingPath.programPath)
        case let .typeMismatch(_, context):
            return .decodingFailed(field: context.codingPath.programPath, reason: context.debugDescription)
        case let .dataCorrupted(context):
            return .decodingFailed(field: context.codingPath.programPath, reason: context.debugDescription)
        @unknown default:
            return .decodingFailed(field: "program", reason: String(describing: decodingError))
        }
    }
}

extension Array where Element == CodingKey {
    var programPath: String {
        guard !isEmpty else {
            return "program"
        }

        return reduce(into: "") { result, key in
            if let index = key.intValue {
                result += "[\(index)]"
            } else if result.isEmpty {
                result += key.stringValue
            } else {
                result += ".\(key.stringValue)"
            }
        }
    }
}
