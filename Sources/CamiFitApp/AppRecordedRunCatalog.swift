import Foundation

public struct AppRecordedRunSummary: Equatable, Identifiable {
    public enum Purpose: String, Equatable {
        case cleanSample
        case noPoseDiagnostic
    }

    public let id: String
    public let displayName: String
    public let presetID: String
    public let url: URL
    public let purpose: Purpose
}

public enum AppRecordedRunCatalog {
    private struct Definition {
        let id: String
        let displayName: String
        let presetID: String
        let filename: String
        let purpose: AppRecordedRunSummary.Purpose
    }

    private static let definitions = [
        Definition(
            id: "squat_two_frames",
            displayName: "Squat sample",
            presetID: "bodyweight_squat",
            filename: "squat_two_frames.jsonl",
            purpose: .cleanSample
        ),
        Definition(
            id: "squat_mixed_no_pose",
            displayName: "Squat no-pose sample",
            presetID: "bodyweight_squat",
            filename: "squat_mixed_no_pose.jsonl",
            purpose: .noPoseDiagnostic
        )
    ]

    public static func defaultSourceCandidates() -> [URL] {
        var candidates: [URL] = []
        if let resourceURL = Bundle.module.url(forResource: "RecordedRuns", withExtension: nil) {
            candidates.append(resourceURL)
        }

        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/CamiFitApp/Resources/RecordedRuns")
        )
        return candidates
    }

    public static func resolveRecordedRuns(from candidates: [URL]) -> (sourceURL: URL?, runs: [AppRecordedRunSummary]) {
        for candidate in candidates {
            let runs = recordedRuns(in: candidate)
            if !runs.isEmpty {
                return (candidate, runs)
            }
        }

        return (nil, [])
    }

    private static func recordedRuns(in directory: URL) -> [AppRecordedRunSummary] {
        definitions.compactMap { definition in
            let url = directory.appendingPathComponent(definition.filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }

            return AppRecordedRunSummary(
                id: definition.id,
                displayName: definition.displayName,
                presetID: definition.presetID,
                url: url,
                purpose: definition.purpose
            )
        }
    }
}
