import CamiFitEngine
import Foundation

public struct AppMockWorkerPoseProviderConfiguration: Equatable {
    public let workerScriptURL: URL
    public let selectedPresetID: String
    public let fixture: String
    public let frameID: Int
    public let timestampMS: Int64
    public let imageSize: [Int]

    public init(
        workerScriptURL: URL,
        selectedPresetID: String = "bodyweight_squat",
        fixture: String = "squat_bottom",
        frameID: Int = 1,
        timestampMS: Int64 = 1_000,
        imageSize: [Int] = [1_280, 720]
    ) {
        self.workerScriptURL = workerScriptURL
        self.selectedPresetID = selectedPresetID
        self.fixture = fixture
        self.frameID = frameID
        self.timestampMS = timestampMS
        self.imageSize = imageSize
    }
}

public enum AppPoseProviderMode: Equatable {
    case recordedRun(id: String)
    case mockWorker(AppMockWorkerPoseProviderConfiguration)
}

public struct AppConfiguredPoseProvider {
    public let mode: AppPoseProviderMode
    public let provider: PoseProvider
    public let selectedPresetID: String
    public let recordedRunID: String?
    public let recordedRunSourceURL: URL?
    public let sourceDescription: String
}

public enum AppPoseProviderFactoryError: Error, Equatable, CustomStringConvertible {
    case recordedRunNotFound(String)

    public var description: String {
        switch self {
        case let .recordedRunNotFound(id):
            return "recorded run not found: \(id)"
        }
    }
}

public struct AppPoseProviderFactory {
    private let recordedRunSourceCandidates: [URL]

    public init(recordedRunSourceCandidates: [URL] = AppRecordedRunCatalog.defaultSourceCandidates()) {
        self.recordedRunSourceCandidates = recordedRunSourceCandidates
    }

    public func configuredProvider(for mode: AppPoseProviderMode) throws -> AppConfiguredPoseProvider {
        switch mode {
        case let .recordedRun(id):
            return try recordedRunProvider(id: id, mode: mode)
        case let .mockWorker(configuration):
            return mockWorkerProvider(configuration: configuration, mode: mode)
        }
    }

    private func recordedRunProvider(id: String, mode: AppPoseProviderMode) throws -> AppConfiguredPoseProvider {
        let resolved = AppRecordedRunCatalog.resolveRecordedRuns(from: recordedRunSourceCandidates)
        guard let run = resolved.runs.first(where: { $0.id == id }) else {
            throw AppPoseProviderFactoryError.recordedRunNotFound(id)
        }

        return AppConfiguredPoseProvider(
            mode: mode,
            provider: MediaPipePoseProvider(jsonlURL: run.url),
            selectedPresetID: run.presetID,
            recordedRunID: run.id,
            recordedRunSourceURL: resolved.sourceURL,
            sourceDescription: "recorded:\(run.id)"
        )
    }

    private func mockWorkerProvider(
        configuration: AppMockWorkerPoseProviderConfiguration,
        mode: AppPoseProviderMode
    ) -> AppConfiguredPoseProvider {
        let provider = PoseWorkerSubprocessProvider(
            workerScriptURL: configuration.workerScriptURL,
            fixture: configuration.fixture,
            frameID: configuration.frameID,
            timestampMS: configuration.timestampMS,
            imageSize: configuration.imageSize
        )

        return AppConfiguredPoseProvider(
            mode: mode,
            provider: provider,
            selectedPresetID: configuration.selectedPresetID,
            recordedRunID: nil,
            recordedRunSourceURL: nil,
            sourceDescription: "mock-worker:\(provider.launchCommandDescription)"
        )
    }
}
