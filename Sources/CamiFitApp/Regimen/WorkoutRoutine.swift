import CamiFitEngine
import Foundation

enum ExerciseRef: Codable, Equatable {
    case preset(id: String)
    case inline(ExerciseProgram)

    private enum CodingKeys: String, CodingKey { case preset, inline }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try c.decodeIfPresent(String.self, forKey: .preset) {
            self = .preset(id: id)
        } else {
            self = .inline(try c.decode(ExerciseProgram.self, forKey: .inline))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .preset(id): try c.encode(id, forKey: .preset)
        case let .inline(program): try c.encode(program, forKey: .inline)
        }
    }
}

struct RoutineBlock: Codable, Equatable {
    var exerciseRef: ExerciseRef
    var sets: Int
    var reps: Int?
    var holdSeconds: Double?
    var restSeconds: Int
}

struct WorkoutRoutine: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var description: String
    var blocks: [RoutineBlock]
}
