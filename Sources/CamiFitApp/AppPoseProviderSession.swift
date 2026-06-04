import CamiFitEngine
import Foundation

public struct AppPoseProviderRunSummary: Equatable {
    public let frameCount: Int
    public let selectedExerciseID: String?
    public let selectedExerciseName: String?
    public let repCount: Int
    public let holdSeconds: Double
    public let holdTargetReached: Bool
    public let diagnosticText: String?
    public let state: AppExerciseSessionState

    public init(
        frameCount: Int,
        selectedExerciseID: String?,
        selectedExerciseName: String?,
        repCount: Int,
        holdSeconds: Double,
        holdTargetReached: Bool,
        diagnosticText: String?,
        state: AppExerciseSessionState
    ) {
        self.frameCount = frameCount
        self.selectedExerciseID = selectedExerciseID
        self.selectedExerciseName = selectedExerciseName
        self.repCount = repCount
        self.holdSeconds = holdSeconds
        self.holdTargetReached = holdTargetReached
        self.diagnosticText = diagnosticText
        self.state = state
    }
}

public final class AppPoseProviderSession {
    private let provider: PoseProvider
    private let viewModel: AppExerciseSessionViewModel

    public init(provider: PoseProvider, viewModel: AppExerciseSessionViewModel = AppExerciseSessionViewModel()) {
        self.provider = provider
        self.viewModel = viewModel
    }

    public func run(selectedPresetID: String) -> AppPoseProviderRunSummary {
        viewModel.loadAvailablePresets()

        do {
            try viewModel.selectPreset(id: selectedPresetID)
        } catch {
            return summary(
                frameCount: 0,
                state: viewModel.state,
                diagnosticText: "Preset not found: \(selectedPresetID)"
            )
        }

        do {
            let frames = try provider.frames()
            let processed = try process(frames: frames)
            return summary(
                frameCount: frames.count,
                state: processed.state,
                diagnosticText: processed.state.diagnosticText ?? processed.diagnosticEvidence
            )
        } catch {
            return summary(
                frameCount: 0,
                state: viewModel.state,
                diagnosticText: "Pose provider failed: \(error)"
            )
        }
    }

    private func summary(
        frameCount: Int,
        state: AppExerciseSessionState,
        diagnosticText: String?
    ) -> AppPoseProviderRunSummary {
        AppPoseProviderRunSummary(
            frameCount: frameCount,
            selectedExerciseID: state.selectedExerciseID,
            selectedExerciseName: state.selectedExerciseName,
            repCount: state.repCount,
            holdSeconds: state.holdSeconds,
            holdTargetReached: state.holdTargetReached,
            diagnosticText: diagnosticText,
            state: state
        )
    }

    private func process(frames: [PoseFrame]) throws -> (state: AppExerciseSessionState, diagnosticEvidence: String?) {
        var diagnosticEvidence: String?

        for endIndex in frames.indices {
            let state = try viewModel.process(frames: Array(frames.prefix(through: endIndex)))
            if diagnosticEvidence == nil {
                diagnosticEvidence = state.diagnosticText
            }
        }

        let finalState = try viewModel.process(frames: frames)
        return (finalState, diagnosticEvidence)
    }
}
