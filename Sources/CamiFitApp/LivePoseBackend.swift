import CamiFitEngine
import Foundation

/// Abstraction over the live pose inference engine: one `predict` per camera
/// frame, decoded into an engine `PoseFrame`. Two implementations exist — the
/// in-process Apple Vision backend (default) and the persistent MediaPipe
/// Python worker subprocess (`CAMIFIT_POSE_BACKEND=mediapipe`).
protocol LivePoseBackend: AnyObject {
    var displayName: String { get }
    /// Extra context lines appended to the error surface when `start()` fails.
    var startFailureDiagnostics: [String] { get }
    func start() throws
    func predict(imagePath: String, frameID: Int, timestampMS: Int64) throws -> PoseFrame?
    func stop()
}

enum LivePoseBackendFactory {
    static func make(environment: [String: String] = ProcessInfo.processInfo.environment) -> any LivePoseBackend {
        switch environment["CAMIFIT_POSE_BACKEND"]?.lowercased() {
        case "mediapipe", "python", "worker":
            return mediaPipeWorkerBackend()
        default:
            return VisionPoseBackend()
        }
    }

    static func mediaPipeWorkerBackend() -> LivePoseWorkerClient {
        let paths = LiveWorkerPaths.resolve()
        return LivePoseWorkerClient(python: paths.python, scriptURL: paths.script, modelURL: paths.model)
    }
}
