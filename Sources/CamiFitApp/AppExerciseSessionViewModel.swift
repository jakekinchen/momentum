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
    public var presetSourceDescription: String?

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
    @Published public private(set) var availableRecordedRuns: [AppRecordedRunSummary] = []
    @Published public private(set) var selectedRecordedRunID: String?
    @Published public private(set) var state = AppExerciseSessionState()
    @Published public private(set) var lastPoseProviderRunSummary: AppPoseProviderRunSummary?
    @Published public private(set) var poseProviderRunStatus: AppPoseProviderRunStatus = .idle
    @Published public private(set) var mockWorkerPreflightStatus: AppMockWorkerPreflightStatus = .idle
    @Published public private(set) var latestHUDState: AppHUDState?
    @Published public private(set) var latestPoseOverlayState = AppPoseOverlayState.empty
    public private(set) var resolvedPresetSourceURL: URL?
    public private(set) var resolvedRecordedRunSourceURL: URL?

    private let presetSourceCandidates: [URL]
    private let recordedRunSourceCandidates: [URL]
    private var selectedProgram: ExerciseProgram?
    private var liveFrames: [PoseFrame] = []

    public convenience init(presetsDirectory: URL) {
        self.init(
            presetSourceCandidates: [presetsDirectory],
            recordedRunSourceCandidates: AppRecordedRunCatalog.defaultSourceCandidates()
        )
    }

    public convenience init(recordedRunsDirectory: URL) {
        self.init(
            presetSourceCandidates: AppExerciseSessionViewModel.defaultPresetSourceCandidates(),
            recordedRunSourceCandidates: [recordedRunsDirectory]
        )
    }

    public convenience init() {
        self.init(
            presetSourceCandidates: AppExerciseSessionViewModel.defaultPresetSourceCandidates(),
            recordedRunSourceCandidates: AppRecordedRunCatalog.defaultSourceCandidates()
        )
    }

    public init(
        presetSourceCandidates: [URL],
        recordedRunSourceCandidates: [URL] = AppRecordedRunCatalog.defaultSourceCandidates()
    ) {
        self.presetSourceCandidates = presetSourceCandidates
        self.recordedRunSourceCandidates = recordedRunSourceCandidates
    }

    public func loadAvailablePresets() {
        let resolved = Self.resolvePresetSummaries(from: presetSourceCandidates)
        availablePresets = resolved.presets
        resolvedPresetSourceURL = resolved.sourceURL
        state.presetSourceDescription = resolved.sourceURL?.path
        if availablePresets.isEmpty {
            state.diagnosticText = "No presets found"
        }

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
            selectedExerciseName: program.name,
            presetSourceDescription: resolvedPresetSourceURL?.path
        )
    }

    public func loadRecordedRuns() {
        let resolved = AppRecordedRunCatalog.resolveRecordedRuns(from: recordedRunSourceCandidates)
        availableRecordedRuns = resolved.runs
        resolvedRecordedRunSourceURL = resolved.sourceURL

        if availableRecordedRuns.isEmpty {
            state.diagnosticText = "No recorded runs found"
            selectedRecordedRunID = nil
            return
        }

        if selectedRecordedRunID == nil {
            selectedRecordedRunID = availableRecordedRuns.first?.id
        }
    }

    @discardableResult
    public func runRecordedRun(id: String) -> AppPoseProviderRunSummary {
        loadRecordedRuns()

        guard let run = availableRecordedRuns.first(where: { $0.id == id }) else {
            let summary = AppPoseProviderRunSummary(
                frameCount: 0,
                selectedExerciseID: state.selectedExerciseID,
                selectedExerciseName: state.selectedExerciseName,
                repCount: state.repCount,
                holdSeconds: state.holdSeconds,
                holdTargetReached: state.holdTargetReached,
                diagnosticText: "Recorded run not found: \(id)",
                state: state
            )
            lastPoseProviderRunSummary = summary
            updateDisplayState(from: summary)
            updateRunStatus(
                from: summary,
                descriptor: AppPoseProviderRunDescriptor(mode: "recorded-run", source: "recorded:\(id)")
            )
            return summary
        }

        selectedRecordedRunID = run.id
        let provider = MediaPipePoseProvider(jsonlURL: run.url)
        return runRecordedProvider(
            provider,
            selectedPresetID: run.presetID,
            statusDescriptor: AppPoseProviderRunDescriptor(mode: "recorded-run", source: "recorded:\(run.id)")
        )
    }

    @discardableResult
    public func runRecordedProvider(
        _ provider: PoseProvider,
        selectedPresetID requestedPresetID: String? = nil
    ) -> AppPoseProviderRunSummary {
        runRecordedProvider(
            provider,
            selectedPresetID: requestedPresetID,
            statusDescriptor: AppPoseProviderRunDescriptor(mode: "provider", source: "direct-provider")
        )
    }

    @discardableResult
    private func runRecordedProvider(
        _ provider: PoseProvider,
        selectedPresetID requestedPresetID: String?,
        statusDescriptor: AppPoseProviderRunDescriptor
    ) -> AppPoseProviderRunSummary {
        poseProviderRunStatus = .running(statusDescriptor)
        loadAvailablePresets()

        guard let presetID = requestedPresetID ?? state.selectedExerciseID ?? availablePresets.first?.id else {
            let summary = AppPoseProviderRunSummary(
                frameCount: 0,
                selectedExerciseID: state.selectedExerciseID,
                selectedExerciseName: state.selectedExerciseName,
                repCount: state.repCount,
                holdSeconds: state.holdSeconds,
                holdTargetReached: state.holdTargetReached,
                diagnosticText: "No preset selected",
                state: state
            )
            lastPoseProviderRunSummary = summary
            updateDisplayState(from: summary)
            updateRunStatus(from: summary, descriptor: statusDescriptor)
            return summary
        }

        let session = AppPoseProviderSession(provider: provider, viewModel: self)
        let summary = session.run(selectedPresetID: presetID)
        lastPoseProviderRunSummary = summary
        updateDisplayState(from: summary)
        updateRunStatus(from: summary, descriptor: statusDescriptor)
        return summary
    }

    @discardableResult
    public func runConfiguredPoseProvider(
        mode: AppPoseProviderMode,
        factory: AppPoseProviderFactory? = nil
    ) -> AppPoseProviderRunSummary {
        let providerFactory = factory ?? AppPoseProviderFactory(recordedRunSourceCandidates: recordedRunSourceCandidates)

        do {
            let configured = try providerFactory.configuredProvider(for: mode)
            let descriptor = Self.runDescriptor(for: configured)
            poseProviderRunStatus = .running(descriptor)
            if let recordedRunID = configured.recordedRunID {
                selectedRecordedRunID = recordedRunID
                resolvedRecordedRunSourceURL = configured.recordedRunSourceURL
            }
            return runRecordedProvider(
                configured.provider,
                selectedPresetID: configured.selectedPresetID,
                statusDescriptor: descriptor
            )
        } catch {
            let descriptor = Self.runDescriptor(for: mode)
            let summary = AppPoseProviderRunSummary(
                frameCount: 0,
                selectedExerciseID: state.selectedExerciseID,
                selectedExerciseName: state.selectedExerciseName,
                repCount: state.repCount,
                holdSeconds: state.holdSeconds,
                holdTargetReached: state.holdTargetReached,
                diagnosticText: "Pose provider configuration failed: \(error)",
                state: state
            )
            lastPoseProviderRunSummary = summary
            updateDisplayState(from: summary)
            updateRunStatus(from: summary, descriptor: descriptor)
            return summary
        }
    }

    @discardableResult
    public func runMockWorkerProvider(
        workerScriptURL: URL = AppExerciseSessionViewModel.defaultMockWorkerScriptURL(),
        selectedPresetID: String = "bodyweight_squat",
        fixture: String = "squat_bottom",
        frameID: Int = 1,
        timestampMS: Int64 = 1_000
    ) -> AppPoseProviderRunSummary {
        let configuration = AppMockWorkerPoseProviderConfiguration(
            workerScriptURL: workerScriptURL,
            selectedPresetID: selectedPresetID,
            fixture: fixture,
            frameID: frameID,
            timestampMS: timestampMS
        )

        return runConfiguredPoseProvider(mode: .mockWorker(configuration))
    }

    @discardableResult
    public func preflightMockWorker(
        workerScriptURL: URL = AppExerciseSessionViewModel.defaultMockWorkerScriptURL()
    ) -> AppMockWorkerPreflightStatus {
        mockWorkerPreflightStatus = .checking(workerScriptURL)

        guard FileManager.default.fileExists(atPath: workerScriptURL.path) else {
            let status = AppMockWorkerPreflightStatus.failed(
                AppMockWorkerPreflightFailure(
                    workerScriptURL: workerScriptURL,
                    diagnosticText: "mock worker script not found: \(workerScriptURL.path)"
                )
            )
            mockWorkerPreflightStatus = status
            return status
        }

        let provider = PoseWorkerSubprocessProvider(workerScriptURL: workerScriptURL)
        do {
            let health = try provider.health()
            let status = AppMockWorkerPreflightStatus.succeeded(
                AppMockWorkerPreflightSuccess(
                    workerScriptURL: workerScriptURL,
                    command: provider.launchCommandDescription,
                    runningMode: health.runningMode,
                    message: health.message
                )
            )
            mockWorkerPreflightStatus = status
            return status
        } catch {
            let status = AppMockWorkerPreflightStatus.failed(
                AppMockWorkerPreflightFailure(
                    workerScriptURL: workerScriptURL,
                    diagnosticText: "mock worker preflight failed: \(error)"
                )
            )
            mockWorkerPreflightStatus = status
            return status
        }
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

    /// Feed one live camera frame: accumulate, re-run the engine over the buffer, and publish
    /// updated reps/form + the skeleton overlay. Swallows engine errors so a single bad frame
    /// never breaks the live loop.
    public func ingestLiveFrame(_ frame: PoseFrame) {
        liveFrames.append(frame)
        do {
            _ = try process(frames: liveFrames)
        } catch {
            state.diagnosticText = "live engine error: \(error)"
        }
        latestPoseOverlayState = AppPoseOverlayState(frame: frame)
    }

    public func resetLiveSession() {
        liveFrames.removeAll()
        state.repCount = 0
        state.holdSeconds = 0
        state.holdTargetReached = false
        state.cueText = nil
        state.diagnosticText = nil
        latestPoseOverlayState = AppPoseOverlayState.empty
    }

    private static func defaultPresetSourceCandidates() -> [URL] {
        var candidates: [URL] = []
        if let resourceURL = Bundle.module.url(forResource: "Presets", withExtension: nil) {
            candidates.append(resourceURL)
        }

        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Presets"))
        candidates.append(RegimenStore.userPresetsDirectory())
        return candidates
    }

    public static func defaultMockWorkerScriptURL(
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> URL {
        currentDirectory.appendingPathComponent("pose_worker/pose_worker.py")
    }

    private static func runDescriptor(for configured: AppConfiguredPoseProvider) -> AppPoseProviderRunDescriptor {
        AppPoseProviderRunDescriptor(
            mode: runModeDescription(for: configured.mode),
            source: configured.sourceDescription
        )
    }

    private static func runDescriptor(for mode: AppPoseProviderMode) -> AppPoseProviderRunDescriptor {
        AppPoseProviderRunDescriptor(
            mode: runModeDescription(for: mode),
            source: runSourceDescription(for: mode)
        )
    }

    private static func runModeDescription(for mode: AppPoseProviderMode) -> String {
        switch mode {
        case .recordedRun:
            return "recorded-run"
        case .mockWorker:
            return "mock-worker"
        }
    }

    private static func runSourceDescription(for mode: AppPoseProviderMode) -> String {
        switch mode {
        case let .recordedRun(id):
            return "recorded:\(id)"
        case let .mockWorker(configuration):
            return "mock-worker:\(configuration.workerScriptURL.path)"
        }
    }

    private static func resolvePresetSummaries(from candidates: [URL]) -> (sourceURL: URL?, presets: [AppPresetSummary]) {
        let merged = mergedPresetSummaries(from: candidates)
        let source = candidates.first { !loadPresetSummaries(from: $0).isEmpty }
        return (source, merged)
    }

    /// Merge every candidate directory; later candidates win on id collision.
    static func mergedPresetSummaries(from candidates: [URL]) -> [AppPresetSummary] {
        var byID: [String: AppPresetSummary] = [:]
        for candidate in candidates {
            for preset in loadPresetSummaries(from: candidate) { byID[preset.id] = preset }
        }
        return byID.values.sorted { $0.name < $1.name }
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

    private func updateDisplayState(from summary: AppPoseProviderRunSummary) {
        latestHUDState = AppHUDState(summary: summary)

        guard summary.diagnosticText == nil, let latestPoseFrame = summary.latestPoseFrame else {
            latestPoseOverlayState = .empty
            return
        }

        latestPoseOverlayState = AppPoseOverlayState(frame: latestPoseFrame)
    }

    private func updateRunStatus(
        from summary: AppPoseProviderRunSummary,
        descriptor: AppPoseProviderRunDescriptor
    ) {
        if let diagnosticText = summary.diagnosticText {
            poseProviderRunStatus = .failed(
                AppPoseProviderRunStatusFailure(descriptor: descriptor, diagnosticText: diagnosticText)
            )
        } else {
            poseProviderRunStatus = .succeeded(
                AppPoseProviderRunStatusSummary(descriptor: descriptor, frameCount: summary.frameCount)
            )
        }
    }
}
