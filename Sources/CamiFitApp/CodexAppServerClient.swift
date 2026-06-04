import Combine
import Foundation

/// Drives a bundled (or installed) `codex app-server` over newline-delimited JSON-RPC and
/// exposes a single-turn streaming chat plus ChatGPT login management.
///
/// Safety posture: the thread runs with `approvalPolicy: "untrusted"` and every approval
/// request the agent raises is auto-declined, so the coach can answer in text but can never
/// execute shell commands, edit files, or touch the network without an explicit (and here,
/// always-denied) prompt. A per-turn watchdog guarantees the UI never hangs on a stalled turn.
final class CodexAppServerClient: ObservableObject {
    enum ConnectionState: Equatable {
        case idle
        case starting
        case ready
        case failed(String)
    }

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var isLoggedIn = false
    @Published private(set) var loginDetail = "Checking sign-in…"

    private var process: Process?
    private var stdin: FileHandle?
    private var readBuffer = Data()
    private var nextID = 1
    private var threadID: String?
    private var responseHandlers: [Int: ([String: Any]) -> Void] = [:]

    private struct ActiveTurn {
        let token: Int
        let onDelta: (String) -> Void
        let onComplete: () -> Void
        let onError: (String) -> Void
    }
    private var activeTurn: ActiveTurn?
    private var turnToken = 0
    private var queuedText: String?

    private let baseInstructions = """
    You are CamiFit's friendly fitness coach. Answer questions about exercise form, reps, \
    holds, and general workout guidance in clear, encouraging text. You are a chat assistant \
    only — never run shell commands, edit files, or use tools. Just reply with helpful text.
    """

    // MARK: - Binary resolution

    /// Prefers a binary bundled in the app, then common install locations.
    static func resolveCodexURL() -> URL? {
        if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let bundled = exeDir.appendingPathComponent("codex")
            if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        }
        for path in ["/opt/homebrew/bin/codex", "/usr/local/bin/codex"] {
            if FileManager.default.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    // MARK: - Lifecycle

    func start() {
        guard process == nil else { return }
        guard let codexURL = Self.resolveCodexURL() else {
            state = .failed("Codex CLI not found. Install it or bundle it with the app.")
            return
        }
        state = .starting

        let proc = Process()
        proc.executableURL = codexURL
        proc.arguments = ["app-server"]
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe
        stdin = stdinPipe.fileHandleForWriting

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.ingest(data) }
        }
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.handleTermination() }
        }

        do {
            try proc.run()
        } catch {
            state = .failed("Could not launch Codex: \(error.localizedDescription)")
            return
        }
        process = proc

        refreshLoginStatus()
        sendRequest(method: "initialize",
                    params: ["clientInfo": ["name": "CamiFit", "version": "0.1.0"],
                             "capabilities": ["experimentalApi": true]]) { [weak self] _ in
            self?.sendNotification("initialized", params: nil)
            self?.startThread()
        }
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        stdin = nil
        threadID = nil
        activeTurn = nil
        responseHandlers.removeAll()
        state = .idle
    }

    private func startThread() {
        sendRequest(method: "thread/start",
                    params: ["approvalPolicy": "untrusted",
                             "baseInstructions": baseInstructions,
                             "cwd": NSTemporaryDirectory()]) { [weak self] result in
            guard let self else { return }
            if let thread = result["thread"] as? [String: Any], let id = thread["id"] as? String {
                self.threadID = id
                self.state = .ready
                if let queued = self.queuedText {
                    self.queuedText = nil
                    self.sendTurn(text: queued)
                }
            } else {
                self.state = .failed("Codex did not return a thread id.")
            }
        }
    }

    private func handleTermination() {
        process = nil
        stdin = nil
        threadID = nil
        if case .failed = state {} else { state = .idle }
        if let turn = activeTurn {
            activeTurn = nil
            turn.onError("Codex stopped unexpectedly.")
        }
    }

    // MARK: - Chat

    /// Sends one user message and streams the assistant reply. Auto-starts the server if needed.
    func startTurn(text: String,
                   onDelta: @escaping (String) -> Void,
                   onComplete: @escaping () -> Void,
                   onError: @escaping (String) -> Void) {
        turnToken += 1
        let token = turnToken
        activeTurn = ActiveTurn(token: token, onDelta: onDelta, onComplete: onComplete, onError: onError)
        scheduleWatchdog(token: token)

        switch state {
        case .ready:
            sendTurn(text: text)
        case .idle, .failed:
            queuedText = text
            start()
        case .starting:
            queuedText = text
        }
    }

    private func sendTurn(text: String) {
        guard let threadID else { queuedText = text; return }
        sendRequest(method: "turn/start",
                    params: ["threadId": threadID,
                             "input": [["type": "text", "text": text]]])
    }

    private func scheduleWatchdog(token: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
            guard let self, let turn = self.activeTurn, turn.token == token else { return }
            self.activeTurn = nil
            turn.onError("Codex did not respond in time.")
        }
    }

    private func finishTurn(_ body: (ActiveTurn) -> Void) {
        guard let turn = activeTurn else { return }
        activeTurn = nil
        body(turn)
    }

    // MARK: - JSON-RPC

    private func sendRequest(method: String, params: Any?, onResult: (([String: Any]) -> Void)? = nil) {
        let id = nextID
        nextID += 1
        var msg: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params { msg["params"] = params }
        if let onResult { responseHandlers[id] = onResult }
        writeMessage(msg)
    }

    private func sendNotification(_ method: String, params: Any?) {
        var msg: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let params { msg["params"] = params }
        writeMessage(msg)
    }

    private func writeMessage(_ msg: [String: Any]) {
        guard let stdin, let data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        var line = data
        line.append(0x0A)
        stdin.write(line)
    }

    private func ingest(_ data: Data) {
        readBuffer.append(data)
        while let newline = readBuffer.firstIndex(of: 0x0A) {
            let lineData = readBuffer.subdata(in: readBuffer.startIndex..<newline)
            readBuffer.removeSubrange(readBuffer.startIndex...newline)
            guard !lineData.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            handle(obj)
        }
    }

    private func handle(_ msg: [String: Any]) {
        let method = msg["method"] as? String

        // Response to one of our requests (has id, no method).
        if method == nil, let id = msg["id"] as? Int {
            if let handler = responseHandlers.removeValue(forKey: id) {
                handler(msg["result"] as? [String: Any] ?? [:])
            }
            return
        }

        guard let method else { return }

        // Server -> client request (has id + method): auto-decline any approval.
        if let id = msg["id"] {
            var reply: [String: Any] = ["jsonrpc": "2.0", "id": id]
            reply["result"] = denialResult(for: method)
            writeMessage(reply)
            return
        }

        // Server notification.
        let params = msg["params"] as? [String: Any] ?? [:]
        switch method {
        case "item/agentMessage/delta":
            if let delta = params["delta"] as? String { activeTurn?.onDelta(delta) }
        case "turn/completed":
            finishTurn { $0.onComplete() }
        case "turn/failed":
            let text = errorText(in: params) ?? "Codex could not complete the turn."
            finishTurn { $0.onError(text) }
        case "error":
            let text = errorText(in: params) ?? "Codex reported an error."
            finishTurn { $0.onError(text) }
        case "account/updated", "account/login/completed":
            refreshLoginStatus()
        default:
            break
        }
    }

    /// v1 approval methods speak `ReviewDecision` ("denied"); v2 `item/*` speak ("decline").
    private func denialResult(for method: String) -> [String: Any] {
        switch method {
        case "execCommandApproval", "applyPatchApproval":
            return ["decision": "denied"]
        default:
            return ["decision": "decline"]
        }
    }

    private func errorText(in params: [String: Any]) -> String? {
        if let message = params["message"] as? String { return message }
        if let error = params["error"] as? [String: Any], let message = error["message"] as? String { return message }
        return nil
    }

    // MARK: - Login (ChatGPT OAuth via the codex CLI)

    func refreshLoginStatus() {
        // `codex login status` prints to stderr, so consider both streams.
        runCodex(["login", "status"]) { [weak self] _, out, err in
            let text = (out + "\n" + err).trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = text.lowercased()
            let loggedIn = lower.contains("logged in") && !lower.contains("not logged in")
            self?.isLoggedIn = loggedIn
            let firstLine = text
                .components(separatedBy: "\n")
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            self?.loginDetail = firstLine ?? (loggedIn ? "Signed in" : "Not signed in")
        }
    }

    /// Runs Codex's browser OAuth flow. Codex stores/refreshes the token in ~/.codex.
    func login() {
        loginDetail = "Opening browser to sign in…"
        runCodex(["login"]) { [weak self] _, _, _ in
            self?.refreshLoginStatus()
        }
    }

    func logout() {
        loginDetail = "Signing out…"
        runCodex(["logout"]) { [weak self] _, _, _ in
            self?.refreshLoginStatus()
        }
    }

    private func runCodex(_ args: [String], completion: @escaping (Int32, String, String) -> Void) {
        guard let codexURL = Self.resolveCodexURL() else {
            completion(127, "", "codex not found")
            return
        }
        let proc = Process()
        proc.executableURL = codexURL
        proc.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.terminationHandler = { finished in
            let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let code = finished.terminationStatus
            DispatchQueue.main.async { completion(code, out, err) }
        }
        do {
            try proc.run()
        } catch {
            completion(127, "", error.localizedDescription)
        }
    }
}
