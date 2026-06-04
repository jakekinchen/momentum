import Foundation

public struct PoseWorkerHealth: Equatable {
    public let ok: Bool
    public let poseReady: Bool
    public let runningMode: String
    public let message: String
}

public enum PoseWorkerSubprocessError: Error, Equatable, CustomStringConvertible {
    case workerScriptNotFound(String)
    case launchFailed(String)
    case nonZeroExit(Int32, String)
    case invalidResponse(String)
    case workerError(String)
    case missingHealthResponse
    case unhealthy(PoseWorkerHealth)
    case missingPoseResponse

    public var description: String {
        switch self {
        case let .workerScriptNotFound(path):
            return "pose worker script not found: \(path)"
        case let .launchFailed(reason):
            return "pose worker launch failed: \(reason)"
        case let .nonZeroExit(status, stderr):
            return "pose worker exited with status \(status): \(stderr)"
        case let .invalidResponse(reason):
            return "invalid pose worker response: \(reason)"
        case let .workerError(message):
            return "pose worker error: \(message)"
        case .missingHealthResponse:
            return "pose worker did not return a health response"
        case let .unhealthy(health):
            return "pose worker unhealthy: ok=\(health.ok) pose_ready=\(health.poseReady) message=\(health.message)"
        case .missingPoseResponse:
            return "pose worker did not return a pose response"
        }
    }
}

public struct PoseWorkerSubprocessProvider: PoseProvider {
    public let launchExecutableURL: URL
    public let launchArguments: [String]
    public let workerScriptURL: URL
    public let fixture: String
    public let frameID: Int
    public let timestampMS: Int64
    public let imageSize: [Int]

    public init(
        launchExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/env"),
        launchArguments: [String] = ["python3"],
        workerScriptURL: URL,
        fixture: String = "standing",
        frameID: Int = 1,
        timestampMS: Int64 = 1_000,
        imageSize: [Int] = [1_280, 720]
    ) {
        self.launchExecutableURL = launchExecutableURL
        self.launchArguments = launchArguments
        self.workerScriptURL = workerScriptURL
        self.fixture = fixture
        self.frameID = frameID
        self.timestampMS = timestampMS
        self.imageSize = imageSize
    }

    public func health() throws -> PoseWorkerHealth {
        try run().health
    }

    public func frames() throws -> [PoseFrame] {
        let result = try run()
        guard let poseJSONLine = result.poseJSONLine else {
            throw PoseWorkerSubprocessError.missingPoseResponse
        }

        return try MediaPipePoseJSONLDecoder.decode(jsonl: poseJSONLine)
    }

    public var launchCommandDescription: String {
        ([launchExecutableURL.path] + launchArguments + [workerScriptURL.path, "--mode", "mock"]).joined(separator: " ")
    }

    private func run() throws -> (health: PoseWorkerHealth, poseJSONLine: String?) {
        guard FileManager.default.fileExists(atPath: workerScriptURL.path) else {
            throw PoseWorkerSubprocessError.workerScriptNotFound(workerScriptURL.path)
        }

        let process = Process()
        process.executableURL = launchExecutableURL
        process.arguments = launchArguments + [workerScriptURL.path, "--mode", "mock"]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw PoseWorkerSubprocessError.launchFailed(String(describing: error))
        }

        let input = try requestJSONL()
        stdinPipe.fileHandleForWriting.write(input)
        stdinPipe.fileHandleForWriting.closeFile()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            throw PoseWorkerSubprocessError.nonZeroExit(process.terminationStatus, stderr)
        }

        return try parseOutput(stdoutData)
    }

    private func requestJSONL() throws -> Data {
        let requests: [[String: Any]] = [
            ["type": "health"],
            [
                "type": "predict",
                "frame_id": frameID,
                "timestamp_ms": timestampMS,
                "fixture": fixture,
                "image_size": imageSize
            ]
        ]

        let lines = try requests.map { request -> String in
            let data = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
            guard let line = String(data: data, encoding: .utf8) else {
                throw PoseWorkerSubprocessError.invalidResponse("request JSON was not UTF-8")
            }
            return line
        }

        return (lines.joined(separator: "\n") + "\n").data(using: .utf8) ?? Data()
    }

    private func parseOutput(_ data: Data) throws -> (health: PoseWorkerHealth, poseJSONLine: String?) {
        guard let output = String(data: data, encoding: .utf8) else {
            throw PoseWorkerSubprocessError.invalidResponse("stdout was not UTF-8")
        }

        var health: PoseWorkerHealth?
        var poseJSONLine: String?

        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            let response = try responseObject(from: line)
            guard let type = response["type"] as? String else {
                throw PoseWorkerSubprocessError.invalidResponse("missing response type")
            }

            switch type {
            case "health":
                health = try parseHealth(response)
            case "pose":
                poseJSONLine = line
            case "error":
                throw PoseWorkerSubprocessError.workerError(response["error"] as? String ?? "unknown worker error")
            default:
                throw PoseWorkerSubprocessError.invalidResponse("unexpected response type \(type)")
            }
        }

        guard let health else {
            throw PoseWorkerSubprocessError.missingHealthResponse
        }

        guard health.ok, health.poseReady else {
            throw PoseWorkerSubprocessError.unhealthy(health)
        }

        return (health, poseJSONLine)
    }

    private func responseObject(from line: String) throws -> [String: Any] {
        guard let data = line.data(using: .utf8) else {
            throw PoseWorkerSubprocessError.invalidResponse("line was not UTF-8")
        }

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PoseWorkerSubprocessError.invalidResponse("line was not a JSON object")
        }

        return object
    }

    private func parseHealth(_ response: [String: Any]) throws -> PoseWorkerHealth {
        guard let ok = response["ok"] as? Bool,
              let poseReady = response["pose_ready"] as? Bool,
              let runningMode = response["running_mode"] as? String,
              let message = response["message"] as? String else {
            throw PoseWorkerSubprocessError.invalidResponse("malformed health response")
        }

        return PoseWorkerHealth(ok: ok, poseReady: poseReady, runningMode: runningMode, message: message)
    }
}
