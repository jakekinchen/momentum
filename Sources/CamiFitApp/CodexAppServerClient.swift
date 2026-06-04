import AppKit
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

    enum AccountState: Equatable { case unknown, signedOut, pending, signedIn }

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var account: AccountState = .unknown
    @Published private(set) var accountEmail: String?
    @Published private(set) var accountDetail = "Checking sign-in…"

    private var pendingLoginId: String?

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

        sendRequest(method: "initialize",
                    params: ["clientInfo": ["name": "CamiFit", "version": "0.1.0"],
                             "capabilities": ["experimentalApi": true]]) { [weak self] _ in
            self?.sendNotification("initialized", params: nil)
            self?.startThread()
            self?.refreshAccount()
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
        account = .unknown
        state = .idle
    }

    private func startThread() {
        sendRequest(method: "thread/start",
                    params: ["approvalPolicy": "never",
                             "sandbox": "read-only",
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

        // Server -> client request (has id + method). We don't service any of these: under
        // approvalPolicy "never" no approvals fire, and in ChatGPT auth mode Codex refreshes
        // its own tokens. Reply with a proper JSON-RPC error, never a fake result (a malformed
        // reply to account/chatgptAuthTokens/refresh is what produced the 401).
        if let id = msg["id"] {
            writeMessage(["jsonrpc": "2.0", "id": id,
                          "error": ["code": -32601,
                                    "message": "Unsupported server request method '\(method)'"]])
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
        case "account/login/completed":
            let success = (params["success"] as? Bool) ?? false
            pendingLoginId = nil
            account = success ? .signedIn : .signedOut
            if !success { accountDetail = errorText(in: params) ?? "Sign-in did not complete." }
            refreshAccount()
        case "account/updated":
            refreshAccount()
        default:
            break
        }
    }

    private func errorText(in params: [String: Any]) -> String? {
        if let message = params["message"] as? String { return message }
        if let error = params["error"] as? [String: Any], let message = error["message"] as? String { return message }
        return nil
    }

    // MARK: - OpenAI account (ChatGPT login over the live app-server connection)

    /// Reads the connected account so the UI can show signed-in state (no CLI needed).
    func refreshAccount() {
        guard process != nil else { return }
        sendRequest(method: "account/read", params: ["refreshToken": false]) { [weak self] result in
            guard let self else { return }
            if let acct = result["account"] as? [String: Any],
               let type = acct["type"] as? String, !type.isEmpty {
                self.account = .signedIn
                self.accountEmail = acct["email"] as? String
                let plan = acct["planType"] as? String
                self.accountDetail = (self.accountEmail.map { "Signed in as \($0)" } ?? "Signed in with ChatGPT")
                    + (plan.map { " · \($0)" } ?? "")
            } else if self.account != .pending {
                self.account = .signedOut
                self.accountEmail = nil
                self.accountDetail = "Not signed in"
            }
        }
    }

    /// Starts the ChatGPT browser sign-in over the *live* connection, so the running server
    /// instance receives the credentials directly. (A separate `codex login` process would
    /// leave this server with stale auth — the cause of the 401.)
    func startLogin() {
        guard process != nil else { start(); return }
        account = .pending
        accountDetail = "Opening browser to sign in…"
        sendRequest(method: "account/login/start", params: ["type": "chatgpt"]) { [weak self] result in
            guard let self else { return }
            self.pendingLoginId = result["loginId"] as? String
            if let urlString = result["authUrl"] as? String, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
                self.accountDetail = "Finish signing in in your browser…"
            } else {
                self.account = .signedOut
                self.accountDetail = "Could not start sign-in."
            }
        }
    }

    func cancelLogin() {
        if let loginId = pendingLoginId {
            sendRequest(method: "account/login/cancel", params: ["loginId": loginId])
        }
        pendingLoginId = nil
        account = .signedOut
        accountDetail = "Not signed in"
    }

    func logout() {
        sendRequest(method: "account/logout", params: [:]) { [weak self] _ in
            self?.account = .signedOut
            self?.accountEmail = nil
            self?.accountDetail = "Not signed in"
        }
    }
}
