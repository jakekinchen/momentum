import CamiFitEngine
import Foundation

public enum RoutineValidationError: Error, Equatable, CustomStringConvertible {
    case emptyRoutine
    case emptyBlock(Int)
    case nonpositiveSets(block: Int, sets: Int)
    case negativeRest(block: Int, restSeconds: Int)
    case bothTargets(block: Int)
    case missingPreset(block: Int, id: String)
    case invalidInlineExercise(block: Int, message: String)
    case incompatibleTarget(block: Int, message: String)
    case invalidTarget(block: Int, message: String)

    public var description: String {
        switch self {
        case .emptyRoutine:
            return "Routine needs at least one exercise."
        case let .emptyBlock(index):
            return "Block \(index + 1) is missing an exercise."
        case let .nonpositiveSets(index, sets):
            return "Block \(index + 1) has invalid sets: \(sets)."
        case let .negativeRest(index, restSeconds):
            return "Block \(index + 1) has invalid rest: \(restSeconds)s."
        case let .bothTargets(index):
            return "Block \(index + 1) has both reps and hold seconds."
        case let .missingPreset(index, id):
            return "Block \(index + 1) uses an unavailable preset: \(id)."
        case let .invalidInlineExercise(index, message):
            return "Block \(index + 1) inline exercise is not runnable: \(message)."
        case let .incompatibleTarget(index, message):
            return "Block \(index + 1) target does not match the exercise: \(message)."
        case let .invalidTarget(index, message):
            return "Block \(index + 1) target is invalid: \(message)."
        }
    }
}

public enum SetTarget: Equatable, CustomStringConvertible {
    case reps(Int)
    case holdSeconds(Double)

    public var description: String {
        switch self {
        case let .reps(reps):
            return "\(reps) reps"
        case let .holdSeconds(seconds):
            return "\(Self.formatSeconds(seconds))s hold"
        }
    }

    public var displayText: String { description }

    public var isReps: Bool {
        if case .reps = self { return true }
        return false
    }

    public static func formatSeconds(_ seconds: Double) -> String {
        if seconds.rounded() == seconds {
            return "\(Int(seconds))"
        }
        return String(format: "%.1f", seconds)
    }
}

public struct RoutineCursor: Equatable {
    public var blockIndex: Int
    public var setIndex: Int

    public init(blockIndex: Int = 0, setIndex: Int = 0) {
        self.blockIndex = blockIndex
        self.setIndex = setIndex
    }
}

public struct ExecutableSet: Equatable, Identifiable {
    public var id: String { "\(blockIndex)-\(setIndex)" }
    public let blockIndex: Int
    public let setIndex: Int
    public let program: ExerciseProgram
    public let target: SetTarget
    public let restSecondsAfterSet: Int

    public var cursor: RoutineCursor {
        RoutineCursor(blockIndex: blockIndex, setIndex: setIndex)
    }
}

public struct ExecutableBlock: Equatable, Identifiable {
    public var id: Int { blockIndex }
    public let blockIndex: Int
    public let source: RoutineBlock
    public let program: ExerciseProgram
    public let target: SetTarget
    public let restSeconds: Int
    public let sets: [ExecutableSet]

    public var title: String { program.name }

    public var targetText: String {
        "\(source.sets)x \(target.displayText)"
    }
}

public struct ExecutableRoutine: Equatable, Identifiable {
    public var id: String { routine.id }
    public let routine: WorkoutRoutine
    public let blocks: [ExecutableBlock]

    public var allSets: [ExecutableSet] {
        blocks.flatMap(\.sets)
    }

    public func set(at cursor: RoutineCursor) -> ExecutableSet? {
        guard blocks.indices.contains(cursor.blockIndex) else { return nil }
        let block = blocks[cursor.blockIndex]
        guard block.sets.indices.contains(cursor.setIndex) else { return nil }
        return block.sets[cursor.setIndex]
    }

    public func block(at cursor: RoutineCursor) -> ExecutableBlock? {
        guard blocks.indices.contains(cursor.blockIndex) else { return nil }
        return blocks[cursor.blockIndex]
    }

    public func nextCursor(after cursor: RoutineCursor, practiceOnly: Bool) -> RoutineCursor? {
        guard let block = block(at: cursor) else { return nil }
        if cursor.setIndex + 1 < block.sets.count {
            return RoutineCursor(blockIndex: cursor.blockIndex, setIndex: cursor.setIndex + 1)
        }
        guard !practiceOnly else { return nil }
        let nextBlock = cursor.blockIndex + 1
        guard blocks.indices.contains(nextBlock) else { return nil }
        return RoutineCursor(blockIndex: nextBlock, setIndex: 0)
    }
}

public struct RoutineCompiler {
    private let presetResolver: (String) throws -> ExerciseProgram
    private let inlineValidator: (ExerciseProgram) -> RegimenValidationError?

    init(
        presetResolver: @escaping (String) throws -> ExerciseProgram,
        inlineValidator: @escaping (ExerciseProgram) -> RegimenValidationError? = RegimenBlockParser.validate(program:)
    ) {
        self.presetResolver = presetResolver
        self.inlineValidator = inlineValidator
    }

    public func compile(_ routine: WorkoutRoutine) throws -> ExecutableRoutine {
        guard !routine.blocks.isEmpty else {
            throw RoutineValidationError.emptyRoutine
        }

        let blocks = try routine.blocks.enumerated().map { index, block in
            try compile(block: block, index: index)
        }
        return ExecutableRoutine(routine: routine, blocks: blocks)
    }

    private func compile(block: RoutineBlock, index: Int) throws -> ExecutableBlock {
        guard block.sets > 0 else {
            throw RoutineValidationError.nonpositiveSets(block: index, sets: block.sets)
        }
        if let restSeconds = block.restSeconds, restSeconds < 0 {
            throw RoutineValidationError.negativeRest(block: index, restSeconds: restSeconds)
        }
        if block.reps != nil, block.holdSeconds != nil {
            throw RoutineValidationError.bothTargets(block: index)
        }

        let program = try resolveProgram(for: block.exerciseRef, blockIndex: index)
        let target = try resolveTarget(for: block, program: program, blockIndex: index)
        let restSeconds = max(0, block.restSeconds ?? 0)
        let sets = (0 ..< block.sets).map { setIndex in
            ExecutableSet(
                blockIndex: index,
                setIndex: setIndex,
                program: program,
                target: target,
                restSecondsAfterSet: restSeconds
            )
        }

        return ExecutableBlock(
            blockIndex: index,
            source: block,
            program: program,
            target: target,
            restSeconds: restSeconds,
            sets: sets
        )
    }

    private func resolveProgram(for ref: ExerciseRef, blockIndex: Int) throws -> ExerciseProgram {
        switch ref {
        case let .preset(id):
            do {
                return try presetResolver(id)
            } catch {
                throw RoutineValidationError.missingPreset(block: blockIndex, id: id)
            }
        case let .inline(program):
            if let error = inlineValidator(program) {
                throw RoutineValidationError.invalidInlineExercise(block: blockIndex, message: String(describing: error))
            }
            return program
        }
    }

    private func resolveTarget(
        for block: RoutineBlock,
        program: ExerciseProgram,
        blockIndex: Int
    ) throws -> SetTarget {
        if let reps = block.reps {
            guard reps > 0 else {
                throw RoutineValidationError.invalidTarget(block: blockIndex, message: "reps must be positive")
            }
            guard program.rep != nil else {
                throw RoutineValidationError.incompatibleTarget(block: blockIndex, message: "reps require a rep-counting exercise")
            }
            return .reps(reps)
        }

        if let holdSeconds = block.holdSeconds {
            guard holdSeconds > 0 else {
                throw RoutineValidationError.invalidTarget(block: blockIndex, message: "holdSeconds must be positive")
            }
            guard program.hold != nil else {
                throw RoutineValidationError.incompatibleTarget(block: blockIndex, message: "holdSeconds require a timed hold exercise")
            }
            return .holdSeconds(holdSeconds)
        }

        if let targetReps = program.set.targetReps {
            guard program.rep != nil else {
                throw RoutineValidationError.incompatibleTarget(block: blockIndex, message: "program target reps require a rep-counting exercise")
            }
            return .reps(targetReps)
        }

        if let targetSeconds = program.set.targetSeconds ?? program.hold?.targetSeconds {
            guard program.hold != nil else {
                throw RoutineValidationError.incompatibleTarget(block: blockIndex, message: "program target seconds require a timed hold exercise")
            }
            return .holdSeconds(targetSeconds)
        }

        throw RoutineValidationError.invalidTarget(block: blockIndex, message: "missing reps or holdSeconds")
    }
}
