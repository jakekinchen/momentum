import AppKit
import Combine
import Foundation

/// Drives a bundled (or installed) `codex app-server` over newline-delimited JSON-RPC and
/// exposes a single-turn streaming chat plus ChatGPT login management.
///
/// Safety posture: the thread runs with `approvalPolicy: "never"` and a read-only sandbox,
/// and every server-to-client request is rejected, so the coach can answer in text but can
/// never execute shell commands or edit files. A per-turn watchdog guarantees the UI never
/// hangs on a stalled turn.
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
    private var shouldStartLoginAfterInitialize = false

    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var stderr: FileHandle?
    private var readBuffer = Data()
    private var stderrTail = ""
    private let stderrLock = NSLock()
    private var nextID = 1
    private var threadID: String?
    private var threadGeneration = 0
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
    private let applicationSupportDirectory: URL
    private let fileManager: FileManager
    private let codexURLResolver: () -> URL?
    private let openURL: (URL) -> Bool

    private static let turnWatchdogSeconds: TimeInterval = 300
    private static let maxStderrTailCharacters = 4_000
    static let coachTurnEffort = "low"

    /// The chat coach must NOT freehand-author exercise programs. Per the FitGraph/KG synthesis
    /// (docs/design/2026-06-04-camifit-fitgraph-synthesis.md), "the graph decides; the LLM never
    /// decides eligibility." The authoring prompt + template below are retained but DISABLED until
    /// a KG-backed ProgramCompiler becomes the author — it targets the same future-exercise grammar
    /// and the same ProgramLoader + FrameSignalProcessor validation gate. Flip to true only then.
    static let exerciseAuthoringEnabled = false

    init(applicationSupportDirectory: URL? = nil,
         fileManager: FileManager = .default,
         codexURLResolver: @escaping () -> URL? = { CodexAppServerClient.resolveCodexURL() },
         openURL: @escaping (URL) -> Bool = { CodexAppServerClient.openURLInWorkspace($0) }) {
        self.fileManager = fileManager
        self.codexURLResolver = codexURLResolver
        self.openURL = openURL
        self.applicationSupportDirectory = applicationSupportDirectory
            ?? Self.defaultApplicationSupportDirectory(fileManager: fileManager)
    }

    private static let exerciseTemplate = #"""
    {
      "schemaVersion": 1,
      "id": "bodyweight_squat",
      "name": "Bodyweight Squat",
      "coordinate_space": "image2d",
      "setup": {
        "required_view": "side",
        "required_landmarks": [
          "primary.hip",
          "primary.knee",
          "primary.ankle",
          "primary.shoulder"
        ],
        "min_visibility": 0.65,
        "primary_side": "auto_lock",
        "mirror_handling": "detect",
        "calibration": {
          "top_pose": {
            "instruction": "Stand tall in frame",
            "capture_seconds": 1.0,
            "signals": [
              "knee",
              "torso_tilt"
            ]
          }
        }
      },
      "landmark_aliases": {
        "shoulder": "primary.shoulder",
        "hip": "primary.hip",
        "knee": "primary.knee",
        "ankle": "primary.ankle"
      },
      "signals": {
        "knee_left": "angle(left.hip, left.knee, left.ankle)",
        "knee_right": "angle(right.hip, right.knee, right.ankle)",
        "knee_raw": "angle(primary.hip, primary.knee, primary.ankle)",
        "torso_raw": "angle_to_vertical(primary.shoulder, primary.hip)",
        "knee_symmetry": "abs(knee_left - knee_right)"
      },
      "filters": {
        "knee": {
          "source": "knee_raw",
          "type": "ema",
          "alpha": 0.35
        },
        "torso_tilt": {
          "source": "torso_raw",
          "type": "median",
          "window_ms": 200
        }
      },
      "validity": {
        "min_signal_confidence": 0.65,
        "phase_signal_invalid_policy": "freeze_then_reset",
        "freeze_ms": 500,
        "reset_after_ms": 1500
      },
      "rep": {
        "phase_signal": "knee",
        "down_when": "knee < 100",
        "down_min_ms": 120,
        "bottom_min_ms": 80,
        "up_when": "knee > 160",
        "up_min_ms": 120,
        "min_rom_deg": 50,
        "cooldown_ms": 250
      },
      "hold": null,
      "form_rules": [
        {
          "id": "depth",
          "when": "phase == 'bottom'",
          "expect": "knee <= 95",
          "min_violation_ms": 0,
          "cue": "Go deeper",
          "severity": "warn",
          "score_weight": 10,
          "cooldown_ms": 1500
        },
        {
          "id": "torso",
          "when": "phase in ['descending','bottom']",
          "expect": "torso_tilt <= 45",
          "min_violation_ms": 250,
          "cue": "Chest up",
          "severity": "warn",
          "score_weight": 8,
          "cooldown_ms": 1500
        },
        {
          "id": "symmetry",
          "when": "phase == 'bottom'",
          "expect": "knee_symmetry <= 20",
          "min_violation_ms": 0,
          "cue": "Even both sides",
          "severity": "info",
          "score_weight": 4,
          "cooldown_ms": 2000
        }
      ],
      "set": {
        "target_reps": 10
      }
    }
    """#

    private var baseInstructions: String {
        let supportedExerciseIDs = AppExerciseTrackingGate.guideReadyPresetIDs
            .sorted()
            .joined(separator: ", ")
        let persona = """
        You are the friendly fitness coach inside Momentum - Your Future Coach. Answer questions about exercise form, reps, \
        holds, and general workout guidance in clear, encouraging text. Never run shell commands or \
        edit files. You may only ask the app to act through the structured future-coach-action \
        block described below; the app validates every action locally before doing anything.

        If the user states a current health or safety limitation in first-person terms, such as \
        knee pain, shoulder pain, a back issue, or an injury, include a short normal reply and \
        exactly one fenced code block tagged future-kg-operation. The block must be JSON:
        {"operation_type":"AddMedicalConstraint","constraint_type":"BodyRegion","value":"left_knee","source_text":"the user's exact limitation text","hard":true,"reason":"why this should affect coaching"}.
        Use lower_snake_case body-region values such as left_knee, right_knee, shoulder, back, \
        wrist, or ankle. Do not say the memory is saved; the Momentum - Your Future Coach app will validate and save \
        it locally if allowed.

        If the app provides Momentum - Your Future Coach local KG fact cards in the user message, treat them as active \
        health/safety constraints for that reply.
        """
        let factInstructions = """
        When the user asks for member context that should come from the local member graph, reply with \
        one short sentence and then end the message with exactly one fenced code block tagged \
        future-kg-fact-request. Use this JSON shape:
        {"schemaVersion":1,"tool":"lookup_member_fact","query":"sleep","prompt":"the user's fact question","reason":"why this local member graph lookup is relevant"}.
        Valid query values are brief, adherence, sleep, changed, message_pattern, and churn. Use these \
        requests for questions such as morning brief, adherence trend, sleep this week, changes since \
        last week, message pattern, or churn risk. Do not invent member facts yourself; the app reads \
        the graph and renders any evidence card locally.
        """
        let actionInstructions = """
        When the user asks to see how to do a supported exercise, check their form on a supported \
        exercise, or start practicing a supported exercise, reply with one short sentence and then end \
        the message with exactly one fenced code block tagged future-coach-action.

        Use this JSON shape:
        {"schemaVersion":1,"tool":"activate_exercise","exerciseID":"bodyweight_squat","mode":"guide","reason":"User asked to see squat form"}.

        Supported exercise IDs are \(supportedExerciseIDs). \
        Other packaged prototype presets require a licensed reference \
        clip before you may activate them from chat. Use mode "guide" for requests like "show me how", mode "camera" for \
        requests like "let me practice", and mode "match_form" for requests like "check my form". \
        Write your prose as if the app action card appears immediately below it.
        """
        let routineInstructions = """
        Workout, plan, and routine generation is executed locally by Momentum - Your Future Coach's KGKit planner. \
        When the user asks for a workout, routine, or plan, interpret the user's request into exactly \
        one fenced code block tagged future-workout-plan after a short normal reply. Use this JSON shape:
        {"schemaVersion":1,"tool":"generate_workout","prompt":"the workout goal in plain user-facing words","minutes":50,"reason":"why this request should use the local planner"}.
        Use the prompt field to preserve important user intent such as lower body, bodyweight, time, \
        equipment, or a requested starting movement. Omit minutes when the user did not specify a \
        duration. Do not emit future-routine JSON, do not list routine exercises yourself, and do not \
        choose exercise eligibility yourself; the app validates the request and the graph decides.
        """
        guard Self.exerciseAuthoringEnabled else {
            return persona + "\n\n" + factInstructions + "\n\n" + actionInstructions + "\n\n" + routineInstructions + "\n\n" + """
            Do not author brand-new future-exercise artifacts or inline ExerciseProgram JSON. If a \
            requested routine needs an unsupported movement, explain the limitation in prose and let \
            the local planner handle any runnable routine.
            """
        }
        return persona + "\n\n" + factInstructions + "\n\n" + actionInstructions + "\n\n" + routineInstructions + "\n\n" + """
        When the user asks you to create a brand-new exercise, include a single fenced code block tagged \
        future-exercise containing a full \
          ExerciseProgram JSON. Keep schemaVersion 1; signals are angle(...) expressions over \
          landmarks like primary.hip/primary.knee/primary.ankle; provide a "rep" block OR a "hold" block.

        Use this exact existing exercise as your ExerciseProgram template:
        \(Self.exerciseTemplate)
        """
    }

    var coachBaseInstructionsForTesting: String {
        baseInstructions
    }

    // MARK: - Binary resolution

    /// Prefers a binary bundled in the app, then common install locations.
    static func resolveCodexURL() -> URL? {
        if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let bundled = exeDir.appendingPathComponent("codex")
            if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        }
        for path in codexCandidatePaths() {
            if FileManager.default.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    static func codexCandidatePaths() -> [String] {
        [
            "/opt/homebrew/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex",
            "/opt/homebrew/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-x64/vendor/x86_64-apple-darwin/bin/codex",
            "/usr/local/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex",
            "/usr/local/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-x64/vendor/x86_64-apple-darwin/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
    }

    static func codexProcessEnvironment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base
        let guiSafeSearchPath = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existingPath = (base["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
        let mergedPath = guiSafeSearchPath + existingPath.filter { !guiSafeSearchPath.contains($0) }
        environment["PATH"] = mergedPath.joined(separator: ":")
        return environment
    }

    private static func openURLInWorkspace(_ url: URL) -> Bool {
        if NSWorkspace.shared.open(url) {
            return true
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = [url.absoluteString]
        do {
            try proc.run()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard process == nil else { return }
        guard let codexURL = codexURLResolver() else {
            failStartup("Codex CLI not found. Install it or bundle it with the app.")
            return
        }
        state = .starting
        readBuffer.removeAll()
        clearStderrTail()

        let proc = Process()
        proc.executableURL = codexURL
        proc.arguments = ["app-server"]
        proc.environment = Self.codexProcessEnvironment()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe
        stdin = stdinPipe.fileHandleForWriting
        stdout = stdoutPipe.fileHandleForReading
        stderr = stderrPipe.fileHandleForReading

        stdout?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.ingest(data) }
        }
        stderr?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.appendStderr(data)
        }
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.handleTermination() }
        }

        do {
            try proc.run()
        } catch {
            failStartup("Could not launch Codex: \(error.localizedDescription)")
            return
        }
        process = proc

        sendRequest(method: "initialize",
                    params: ["clientInfo": ["name": ProductBrand.fullName, "version": "0.1.0"],
                             "capabilities": ["experimentalApi": true]]) { [weak self] _ in
            guard let self else { return }
            self.sendNotification("initialized", params: nil)
            self.startThread()
            if self.shouldStartLoginAfterInitialize {
                self.beginLoginRequest()
            } else {
                self.refreshAccount()
            }
        }
    }

    private func failStartup(_ message: String) {
        state = .failed(message)
        shouldStartLoginAfterInitialize = false
        account = .signedOut
        accountEmail = nil
        accountDetail = message
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        stdout?.readabilityHandler = nil
        stderr?.readabilityHandler = nil
        process = nil
        stdin = nil
        stdout = nil
        stderr = nil
        threadID = nil
        threadGeneration += 1
        activeTurn = nil
        responseHandlers.removeAll()
        shouldStartLoginAfterInitialize = false
        pendingLoginId = nil
        clearStderrTail()
        account = .unknown
        state = .idle
    }

    func resetChatSession() {
        turnToken += 1
        activeTurn = nil
        queuedText = nil
        threadID = nil

        guard process != nil else {
            if case .failed = state {} else { state = .idle }
            return
        }
        guard state != .starting else { return }

        threadGeneration += 1
        state = .starting
        startThread()
    }

    private func startThread() {
        let generation = threadGeneration
        let coachWorkspace: URL
        do {
            coachWorkspace = try prepareCoachThreadWorkspace()
        } catch {
            let message = "Could not prepare Codex coach workspace: \(error.localizedDescription)"
            queuedText = nil
            state = .failed(message)
            finishTurn { $0.onError(message) }
            return
        }

        sendRequest(method: "thread/start",
                    params: ["approvalPolicy": "never",
                             "personality": "friendly",
                             "sandbox": "read-only",
                             "baseInstructions": baseInstructions,
                             "cwd": coachWorkspace.path]) { [weak self] result in
            guard let self else { return }
            guard generation == self.threadGeneration else { return }
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

    static func defaultApplicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        if let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return url
        }
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
    }

    static func coachThreadWorkspaceURL(applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory
            .appendingPathComponent("CamiFit", isDirectory: true)
            .appendingPathComponent("AgentThreads", isDirectory: true)
            .appendingPathComponent("Coach", isDirectory: true)
    }

    func prepareCoachThreadWorkspace() throws -> URL {
        let url = Self.coachThreadWorkspaceURL(applicationSupportDirectory: applicationSupportDirectory)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func appendStderr(_ data: Data) {
        let fragment = String(decoding: data, as: UTF8.self)
        stderrLock.lock()
        stderrTail += fragment
        if stderrTail.count > Self.maxStderrTailCharacters {
            stderrTail = String(stderrTail.suffix(Self.maxStderrTailCharacters))
        }
        stderrLock.unlock()
    }

    private func clearStderrTail() {
        stderrLock.lock()
        stderrTail = ""
        stderrLock.unlock()
    }

    private func currentStderrTail() -> String {
        stderrLock.lock()
        let tail = stderrTail
        stderrLock.unlock()
        return tail
    }

    private func codexTerminationDetail() -> String {
        let stderrText = currentStderrTail().trimmingCharacters(in: .whitespacesAndNewlines)
        if stderrText.localizedCaseInsensitiveContains("env: node")
            || stderrText.localizedCaseInsensitiveContains("node: no such file") {
            return "Codex could not start because Node was not found. Install Codex's native binary or make Homebrew's Node available."
        }
        guard !stderrText.isEmpty else {
            return "Codex stopped before sign-in."
        }
        let lines = stderrText
            .split(whereSeparator: \.isNewline)
            .suffix(2)
            .map(String.init)
        return "Codex stopped before sign-in: \(lines.joined(separator: " "))"
    }

    private func handleTermination() {
        let wasStarting = state == .starting
        let wasPendingLogin = account == .pending || shouldStartLoginAfterInitialize || pendingLoginId != nil

        stdout?.readabilityHandler = nil
        stderr?.readabilityHandler = nil
        if let stderrData = stderr?.readDataToEndOfFile(), !stderrData.isEmpty {
            appendStderr(stderrData)
        }
        let terminationDetail = codexTerminationDetail()
        process = nil
        stdin = nil
        stdout = nil
        stderr = nil
        threadID = nil
        pendingLoginId = nil
        shouldStartLoginAfterInitialize = false
        if wasStarting || wasPendingLogin {
            state = .failed(terminationDetail)
            account = .signedOut
            accountEmail = nil
            accountDetail = terminationDetail
        } else if case .failed = state {} else {
            state = .idle
        }
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
                             "effort": Self.coachTurnEffort,
                             "summary": "none",
                             "input": [["type": "text", "text": text]]])
    }

    private func scheduleWatchdog(token: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.turnWatchdogSeconds) { [weak self] in
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
        guard process != nil else {
            account = .unknown
            accountDetail = "Starting Codex…"
            start()
            return
        }
        guard state != .starting else {
            if account != .pending {
                accountDetail = "Checking sign-in…"
            }
            return
        }
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
        if process == nil {
            shouldStartLoginAfterInitialize = true
            account = .pending
            accountDetail = "Starting Codex sign-in…"
            start()
            return
        }
        if state == .starting {
            shouldStartLoginAfterInitialize = true
            account = .pending
            accountDetail = "Waiting for Codex to finish starting…"
            return
        }
        beginLoginRequest()
    }

    private func beginLoginRequest() {
        shouldStartLoginAfterInitialize = false
        account = .pending
        accountDetail = "Opening browser to sign in…"
        sendRequest(method: "account/login/start", params: ["type": "chatgpt"]) { [weak self] result in
            guard let self else { return }
            self.pendingLoginId = result["loginId"] as? String
            if let urlString = result["authUrl"] as? String, let url = URL(string: urlString) {
                if self.openURL(url) {
                    self.accountDetail = "Finish signing in in your browser…"
                } else {
                    self.account = .signedOut
                    self.accountDetail = "Could not open sign-in URL."
                }
            } else {
                self.account = .signedOut
                self.accountDetail = "Could not start sign-in."
            }
        }
    }

    func cancelLogin() {
        shouldStartLoginAfterInitialize = false
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
