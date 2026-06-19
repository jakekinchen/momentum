import CamiFitEngine
import Darwin
import Foundation

/// Drives a persistent `pose_worker.py --mode mediapipe` subprocess: one process, one
/// `predict` request per live camera frame, decoded into a `PoseFrame`.
final class LivePoseWorkerClient {
    enum LiveWorkerError: LocalizedError {
        case notRunning
        case notRunningWithStderr(String)
        case launchFailed(String)
        case unhealthy(String)
        case timeout(String?)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .notRunning: return "pose worker is not running"
            case let .notRunningWithStderr(stderr):
                return "pose worker exited before responding: \(stderr)"
            case let .launchFailed(message):
                return "pose worker launch failed: \(message)"
            case let .unhealthy(message): return "pose worker not ready: \(message)"
            case let .timeout(stderr):
                if let stderr, !stderr.isEmpty {
                    return "pose worker did not respond in time: \(stderr)"
                }
                return "pose worker did not respond in time"
            case let .decode(message): return "pose worker response decode failed: \(message)"
            }
        }
    }

    private let python: LiveWorkerPythonCommand
    private let scriptURL: URL
    private let modelURL: URL
    private let queue = DispatchQueue(label: "camifit.live-pose-worker")

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutFD: Int32 = -1
    private var stderrFD: Int32 = -1
    private var buffer = Data()
    private var stderrBuffer = Data()

    init(python: LiveWorkerPythonCommand, scriptURL: URL, modelURL: URL) {
        self.python = python
        self.scriptURL = scriptURL
        self.modelURL = modelURL
    }

    func start() throws {
        try queue.sync {
            let process = Process()
            process.executableURL = python.executableURL
            var arguments = python.argumentsPrefix
            if python.invokesScript {
                arguments.append(scriptURL.path)
            }
            arguments += ["--mode", "mediapipe", "--model", modelURL.path]
            process.arguments = arguments
            process.currentDirectoryURL = python.invokesScript
                ? scriptURL.deletingLastPathComponent().deletingLastPathComponent()
                : python.executableURL.deletingLastPathComponent()
            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONUNBUFFERED"] = "1"
            process.environment = environment
            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
            } catch {
                throw LiveWorkerError.launchFailed(String(describing: error))
            }
            self.process = process
            self.stdinHandle = stdin.fileHandleForWriting
            self.stdoutFD = stdout.fileHandleForReading.fileDescriptor
            self.stderrFD = stderr.fileHandleForReading.fileDescriptor
            _ = fcntl(self.stderrFD, F_SETFL, O_NONBLOCK)
            self.buffer.removeAll()
            self.stderrBuffer.removeAll()

            // Health handshake.
            let healthTimeout: TimeInterval = python.invokesScript ? 12 : 45
            let health = try self.requestLocked(["type": "health"], timeout: healthTimeout)
            let ok = (health["ok"] as? Bool) ?? false
            let ready = (health["pose_ready"] as? Bool) ?? false
            guard ok, ready else {
                let message = (health["message"] as? String) ?? "model not ready"
                self.stopLocked()
                throw LiveWorkerError.unhealthy(message)
            }
        }
    }

    func predict(imagePath: String, frameID: Int, timestampMS: Int64) throws -> PoseFrame? {
        try queue.sync {
            let response = try requestLocked([
                "type": "predict",
                "frame_id": frameID,
                "image_path": imagePath,
                "timestamp_ms": timestampMS
            ], timeout: 6)
            guard (response["type"] as? String) == "pose" else {
                if let error = response["error"] as? String { throw LiveWorkerError.decode(error) }
                return nil
            }
            let line = try JSONSerialization.data(withJSONObject: response)
            guard let jsonl = String(data: line, encoding: .utf8) else { return nil }
            return try MediaPipePoseJSONLDecoder.decode(jsonl: jsonl).first
        }
    }

    func stop() {
        queue.sync { stopLocked() }
    }

    // MARK: - Locked helpers (run on `queue`)

    private func requestLocked(_ request: [String: Any], timeout: TimeInterval) throws -> [String: Any] {
        guard let stdinHandle, process?.isRunning == true else {
            throw notRunningErrorLocked()
        }
        let payload = try JSONSerialization.data(withJSONObject: request)
        stdinHandle.write(payload)
        stdinHandle.write(Data([0x0A]))
        let line = try readLineLocked(timeout: timeout)
        guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw LiveWorkerError.decode("response was not a JSON object")
        }
        return object
    }

    private func readLineLocked(timeout: TimeInterval) throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<newline)
                buffer.removeSubrange(buffer.startIndex...newline)
                if line.isEmpty { continue }
                return line
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { throw LiveWorkerError.timeout(stderrTailLocked()) }
            guard waitReadable(fd: stdoutFD, timeout: min(remaining, 0.1)) else { continue }
            var chunk = [UInt8](repeating: 0, count: 8192)
            let count = chunk.withUnsafeMutableBytes { Darwin.read(stdoutFD, $0.baseAddress, $0.count) }
            if count > 0 {
                buffer.append(contentsOf: chunk.prefix(count))
            } else if count == 0 {
                throw notRunningErrorLocked()
            }
        }
    }

    private func notRunningErrorLocked() -> LiveWorkerError {
        let stderr = stderrTailLocked()
        if let stderr, !stderr.isEmpty {
            return .notRunningWithStderr(stderr)
        }
        return .notRunning
    }

    private func stderrTailLocked() -> String? {
        guard stderrFD >= 0 else { return nil }
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = chunk.withUnsafeMutableBytes { Darwin.read(stderrFD, $0.baseAddress, $0.count) }
            if count > 0 {
                stderrBuffer.append(contentsOf: chunk.prefix(count))
            } else {
                break
            }
        }
        guard !stderrBuffer.isEmpty else { return nil }
        let text = String(data: stderrBuffer, encoding: .utf8) ?? "<non-utf8 stderr>"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.suffix(1_600))
    }

    private func waitReadable(fd: Int32, timeout: TimeInterval) -> Bool {
        var set = fd_set()
        _ = withUnsafeMutablePointer(to: &set) { ptr in
            memset(ptr, 0, MemoryLayout<fd_set>.size)
        }
        let intOffset = Int(fd) / 32
        let bitOffset = Int(fd) % 32
        withUnsafeMutableBytes(of: &set.fds_bits) { raw in
            raw.bindMemory(to: Int32.self)[intOffset] |= Int32(1 << bitOffset)
        }
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
        return select(fd + 1, &set, nil, nil, &tv) > 0
    }

    private func stopLocked() {
        stdinHandle?.closeFile()
        if process?.isRunning == true { process?.terminate() }
        process = nil
        stdinHandle = nil
        stdoutFD = -1
        stderrFD = -1
        buffer.removeAll()
        stderrBuffer.removeAll()
    }
}

extension LivePoseWorkerClient: LivePoseBackend {
    var displayName: String { "MediaPipe pose worker subprocess" }

    var startFailureDiagnostics: [String] {
        [
            "Python: \(python.displayName)",
            "Worker: \(scriptURL.path)",
            "Model: \(modelURL.path)"
        ]
    }
}
