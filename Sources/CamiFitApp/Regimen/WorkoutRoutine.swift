import CamiFitEngine
import Foundation

public enum ExerciseRef: Codable, Equatable {
    case preset(id: String)
    case inline(ExerciseProgram)

    private enum CodingKeys: String, CodingKey { case preset, inline }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try c.decodeIfPresent(String.self, forKey: .preset) {
            self = .preset(id: id)
        } else {
            self = .inline(try c.decode(ExerciseProgram.self, forKey: .inline))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .preset(id): try c.encode(id, forKey: .preset)
        case let .inline(program): try c.encode(program, forKey: .inline)
        }
    }
}

public struct RoutineBlock: Codable, Equatable {
    public var exerciseRef: ExerciseRef
    public var sets: Int
    public var reps: Int?
    public var holdSeconds: Double?
    public var restSeconds: Int?

    public init(
        exerciseRef: ExerciseRef,
        sets: Int,
        reps: Int? = nil,
        holdSeconds: Double? = nil,
        restSeconds: Int? = nil
    ) {
        self.exerciseRef = exerciseRef
        self.sets = sets
        self.reps = reps
        self.holdSeconds = holdSeconds
        self.restSeconds = restSeconds
    }
}

public struct WorkoutRoutine: Codable, Equatable, Identifiable {
    public static let currentSchemaVersion = 1
    public static let currentArtifactType = "routine"

    public var schemaVersion: Int
    public var artifactType: String
    public var id: String
    public var name: String
    public var description: String?
    public var blocks: [RoutineBlock]

    public init(
        schemaVersion: Int = WorkoutRoutine.currentSchemaVersion,
        artifactType: String = WorkoutRoutine.currentArtifactType,
        id: String,
        name: String,
        description: String? = nil,
        blocks: [RoutineBlock]
    ) {
        self.schemaVersion = schemaVersion
        self.artifactType = artifactType
        self.id = id
        self.name = name
        self.description = description
        self.blocks = blocks
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case artifactType
        case id
        case name
        case description
        case blocks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
            ?? Self.currentSchemaVersion
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Only routine schemaVersion \(Self.currentSchemaVersion) is supported."
            )
        }

        let artifactType = try container.decodeIfPresent(String.self, forKey: .artifactType)
            ?? Self.currentArtifactType
        guard artifactType == Self.currentArtifactType else {
            throw DecodingError.dataCorruptedError(
                forKey: .artifactType,
                in: container,
                debugDescription: "Expected artifactType '\(Self.currentArtifactType)'."
            )
        }

        let id = try container.decode(String.self, forKey: .id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = try container.decode(String.self, forKey: .name)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "Routine id must not be empty."
            )
        }
        guard !name.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .name,
                in: container,
                debugDescription: "Routine name must not be empty."
            )
        }

        self.schemaVersion = schemaVersion
        self.artifactType = artifactType
        self.id = id
        self.name = name
        self.description = try container.decodeIfPresent(String.self, forKey: .description)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.blocks = try container.decode([RoutineBlock].self, forKey: .blocks)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(artifactType, forKey: .artifactType)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(blocks, forKey: .blocks)
    }

    func hasSameContent(as other: WorkoutRoutine) -> Bool {
        schemaVersion == other.schemaVersion
            && artifactType == other.artifactType
            && name == other.name
            && description == other.description
            && blocks == other.blocks
    }
}
