import CamiFitEngine
import Foundation

struct RegimenStore {
    let root: URL

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CamiFit", isDirectory: true)
    }

    static func userPresetsDirectory() -> URL { RegimenStore().presetsDir }

    var presetsDir: URL { root.appendingPathComponent("Presets", isDirectory: true) }
    var routinesDir: URL { root.appendingPathComponent("Routines", isDirectory: true) }

    @discardableResult
    func saveExercise(_ program: ExerciseProgram) throws -> URL {
        try FileManager.default.createDirectory(at: presetsDir, withIntermediateDirectories: true)
        let url = presetsDir.appendingPathComponent("\(program.id).json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(program).write(to: url)
        return url
    }

    @discardableResult
    func saveRoutine(_ routine: WorkoutRoutine) throws -> URL {
        try FileManager.default.createDirectory(at: routinesDir, withIntermediateDirectories: true)
        let url = routinesDir.appendingPathComponent("\(routine.id).json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(routine).write(to: url)
        return url
    }

    func loadRoutines() -> [WorkoutRoutine] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: routinesDir, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(WorkoutRoutine.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name < $1.name }
    }
}
