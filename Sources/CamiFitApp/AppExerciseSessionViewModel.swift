import CamiFitEngine
import Foundation

public struct AppPresetSummary: Equatable, Identifiable {
    public enum ExerciseKind: String, Equatable {
        case reps
        case hold
    }

    public let id: String
    public let name: String
    public let kind: ExerciseKind
    public let url: URL
}

public struct AppExerciseSessionState: Equatable {
    public var selectedExerciseID: String?
    public var selectedExerciseName: String?
    public var repCount: Int = 0
    public var holdSeconds: Double = 0
    public var holdTargetReached: Bool = false
    public var cueText: String?
    public var scoreText: String?
    public var diagnosticText: String?

    public var holdProgressText: String {
        if holdTargetReached {
            return String(format: "%.1fs done", holdSeconds)
        }

        return String(format: "%.1fs", holdSeconds)
    }
}

public enum AppExerciseSessionError: Error, Equatable {
    case presetNotFound(String)
}

public final class AppExerciseSessionViewModel: ObservableObject {
    @Published public private(set) var availablePresets: [AppPresetSummary] = []
    @Published public private(set) var state = AppExerciseSessionState()

    private let presetsDirectory: URL
    private var selectedProgram: ExerciseProgram?

    public init(presetsDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Presets")) {
        self.presetsDirectory = presetsDirectory
    }

    public func loadAvailablePresets() {
        availablePresets = Self.loadPresetSummaries(from: presetsDirectory)
        if state.selectedExerciseID == nil, let first = availablePresets.first {
            try? selectPreset(id: first.id)
        }
    }

    public func selectPreset(id: String) throws {
        guard let preset = availablePresets.first(where: { $0.id == id }) else {
            throw AppExerciseSessionError.presetNotFound(id)
        }

        let program = try ProgramLoader.load(from: preset.url)
        selectedProgram = program
        state = AppExerciseSessionState(
            selectedExerciseID: program.id,
            selectedExerciseName: program.name
        )
    }

    @discardableResult
    public func process(frames: [PoseFrame]) throws -> AppExerciseSessionState {
        guard let selectedProgram else {
            loadAvailablePresets()
            guard self.selectedProgram != nil else {
                return state
            }

            return try process(frames: frames)
        }

        var recorder = try EngineTraceRecorder(program: selectedProgram)
        let trace = recorder.record(frames: frames)
        guard let last = trace.last else {
            return state
        }

        state.repCount = last.rep.repCount

        if let hold = last.hold {
            state.holdSeconds = hold.heldSeconds
            state.holdTargetReached = hold.targetReached
        } else {
            state.holdSeconds = 0
            state.holdTargetReached = false
        }

        state.cueText = last.formSummary.selectedCue
        state.scoreText = last.formSummary.score.map { String(format: "%.3f", $0) }
        state.diagnosticText = diagnosticText(from: last)
        return state
    }

    private static func loadPresetSummaries(from directory: URL) -> [AppPresetSummary] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let program = try? ProgramLoader.load(from: url) else {
                    return nil
                }

                let kind: AppPresetSummary.ExerciseKind = program.hold == nil ? .reps : .hold
                return AppPresetSummary(id: program.id, name: program.name, kind: kind, url: url)
            }
            .sorted { $0.name < $1.name }
    }

    private func diagnosticText(from traceFrame: EngineTraceFrame) -> String? {
        if let invalidReason = traceFrame.rep.invalidReason {
            return invalidReason
        }

        if traceFrame.hold?.valid == false {
            return traceFrame.hold?.notAccumulatingReason
        }

        return nil
    }
}
