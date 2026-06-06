import CamiFitEngine
import Foundation

public struct RegimenStore {
    let root: URL

    public init(root: URL? = nil) {
        self.root = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CamiFit", isDirectory: true)
    }

    static func userPresetsDirectory() -> URL { RegimenStore().presetsDir }

    var presetsDir: URL { root.appendingPathComponent("Presets", isDirectory: true) }
    var routinesDir: URL { root.appendingPathComponent("Routines", isDirectory: true) }

    @discardableResult
    public func saveExercise(_ program: ExerciseProgram) throws -> URL {
        try FileManager.default.createDirectory(at: presetsDir, withIntermediateDirectories: true)
        let url = presetsDir.appendingPathComponent("\(program.id).json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(program).write(to: url)
        return url
    }

    @discardableResult
    func saveRoutine(_ routine: WorkoutRoutine) throws -> URL {
        try FileManager.default.createDirectory(at: routinesDir, withIntermediateDirectories: true)
        let (url, routineToSave) = try uniqueRoutineDestination(for: routine)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(routineToSave).write(to: url)
        return url
    }

    func loadRoutines() -> [WorkoutRoutine] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: routinesDir, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(WorkoutRoutine.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name < $1.name }
    }

    private func uniqueRoutineDestination(for routine: WorkoutRoutine) throws -> (URL, WorkoutRoutine) {
        let baseID = Self.normalizedRoutineID(routine.id, fallbackName: routine.name)
        var suffix: Int?

        while true {
            let candidateID = suffix.map { "\(baseID)-\($0)" } ?? baseID
            let url = routinesDir.appendingPathComponent("\(candidateID).json")
            var candidate = routine
            candidate.id = candidateID

            guard FileManager.default.fileExists(atPath: url.path) else {
                return (url, candidate)
            }

            if let data = try? Data(contentsOf: url),
               let existing = try? JSONDecoder().decode(WorkoutRoutine.self, from: data),
               existing.hasSameContent(as: candidate) {
                return (url, existing)
            }

            suffix = (suffix ?? 1) + 1
        }
    }

    static func normalizedRoutineID(_ rawID: String, fallbackName: String) -> String {
        let source = rawID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallbackName
            : rawID
        var output = ""
        var lastWasDash = false

        for scalar in source.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                output.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if scalar == "-" || scalar == "_" || CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !output.isEmpty, !lastWasDash {
                    output.append("-")
                    lastWasDash = true
                }
            }
        }

        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "routine" : trimmed
    }
}
