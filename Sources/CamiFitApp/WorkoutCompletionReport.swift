import Foundation

public enum WorkoutCompletionScope: String, Codable, Equatable {
    case exercise
    case routine
}

public struct WorkoutCompletionReport: Codable, Equatable {
    let schemaVersion: Int
    let artifactType: String
    let scope: WorkoutCompletionScope
    let name: String
    let durationSeconds: Int
    let completedSets: Int
    let completedExercises: Int
    let exerciseNames: [String]
    let finalProgressText: String
    let formSignals: [String]
    let cameraIssues: [String]
    let safetyContext: [String]

    init(
        schemaVersion: Int = 1,
        artifactType: String = "workoutResult",
        scope: WorkoutCompletionScope,
        name: String,
        durationSeconds: Int,
        completedSets: Int,
        completedExercises: Int,
        exerciseNames: [String],
        finalProgressText: String,
        formSignals: [String] = [],
        cameraIssues: [String] = [],
        safetyContext: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.artifactType = artifactType
        self.scope = scope
        self.name = name
        self.durationSeconds = durationSeconds
        self.completedSets = completedSets
        self.completedExercises = completedExercises
        self.exerciseNames = exerciseNames
        self.finalProgressText = finalProgressText
        self.formSignals = formSignals
        self.cameraIssues = cameraIssues
        self.safetyContext = safetyContext
    }

    init(summary: RoutineCompletionSummary, safetyContext: [String] = []) {
        self.init(
            scope: summary.scope,
            name: summary.routineName,
            durationSeconds: summary.durationSeconds,
            completedSets: summary.completedSets,
            completedExercises: summary.completedBlocks,
            exerciseNames: summary.completedExerciseNames,
            finalProgressText: summary.finalProgressText,
            formSignals: summary.formSignals,
            cameraIssues: summary.cameraIssues,
            safetyContext: safetyContext
        )
    }
}

enum WorkoutDebriefPrompt {
    static func makePrompt(for report: WorkoutCompletionReport) -> String {
        let payload: String
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(report)
            payload = String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            payload = "{}"
        }

        return """
        Interpret this workout result like a coach. Give a concise debrief with what went well, \
        what to adjust next time, and one practical next step. Do not repeat the raw JSON.

        ```future-workout-result
        \(payload)
        ```
        """
    }
}
