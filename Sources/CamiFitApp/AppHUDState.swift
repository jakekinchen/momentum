import Foundation

public struct AppHUDState: Equatable {
    public let presetID: String?
    public let presetName: String?
    public let frameCount: Int
    public let repCount: Int
    public let holdProgressText: String
    public let cueText: String?
    public let diagnosticText: String?

    public init(summary: AppPoseProviderRunSummary) {
        presetID = summary.selectedExerciseID
        presetName = summary.selectedExerciseName
        frameCount = summary.frameCount
        repCount = summary.repCount
        holdProgressText = summary.state.holdProgressText
        cueText = summary.state.cueText
        diagnosticText = summary.diagnosticText ?? summary.state.diagnosticText
    }
}
