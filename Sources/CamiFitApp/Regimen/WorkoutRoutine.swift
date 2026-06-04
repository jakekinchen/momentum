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
    public var restSeconds: Int
}

public struct WorkoutRoutine: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var description: String
    public var blocks: [RoutineBlock]
}
