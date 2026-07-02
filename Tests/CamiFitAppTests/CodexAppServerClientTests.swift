import XCTest
@testable import CamiFitApp

final class CodexAppServerClientTests: XCTestCase {
    func testCoachThreadWorkspaceUsesApplicationSupportNamespace() {
        let appSupport = URL(fileURLWithPath: "/example/Application Support", isDirectory: true)
        let workspace = CodexAppServerClient.coachThreadWorkspaceURL(
            applicationSupportDirectory: appSupport
        )

        XCTAssertEqual(
            workspace.path,
            "/example/Application Support/CamiFit/AgentThreads/Coach"
        )
        XCTAssertNotEqual(workspace.path, "/tmp")
    }

    func testPrepareCoachThreadWorkspaceCreatesDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAppServerClientTests-\(UUID().uuidString)", isDirectory: true)
        let client = CodexAppServerClient(applicationSupportDirectory: directory)

        let workspace = try client.prepareCoachThreadWorkspace()

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertEqual(
            workspace.path,
            directory
                .appendingPathComponent("CamiFit", isDirectory: true)
                .appendingPathComponent("AgentThreads", isDirectory: true)
                .appendingPathComponent("Coach", isDirectory: true)
                .path
            )
    }

    func testCodexCandidatePathsPreferNativeBinaryBeforeHomebrewShim() {
        let paths = CodexAppServerClient.codexCandidatePaths()
        let nativeCodex = "/opt/homebrew/lib/node_modules/@openai/codex/node_modules/@openai/codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex"
        let homebrewShim = "/opt/homebrew/bin/codex"

        XCTAssertEqual(paths.first, nativeCodex)
        XCTAssertLessThan(
            paths.firstIndex(of: nativeCodex) ?? Int.max,
            paths.firstIndex(of: homebrewShim) ?? Int.min
        )
    }

    func testCodexProcessEnvironmentPrependsHomebrewPathsForGuiLaunches() {
        let environment = CodexAppServerClient.codexProcessEnvironment(base: ["PATH": "/usr/bin:/bin:/custom/bin"])
        let pathParts = environment["PATH"]?.split(separator: ":").map(String.init) ?? []

        XCTAssertEqual(Array(pathParts.prefix(2)), ["/opt/homebrew/bin", "/usr/local/bin"])
        XCTAssertTrue(pathParts.contains("/usr/bin"))
        XCTAssertTrue(pathParts.contains("/custom/bin"))
        XCTAssertEqual(pathParts.filter { $0 == "/usr/bin" }.count, 1)
    }

    func testResetChatSessionStartsFreshCoachThread() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAppServerClientTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fakeCodexURL = directory.appendingPathComponent("fake-codex")
        let transcriptURL = URL(fileURLWithPath: fakeCodexURL.path + ".log")
        let fakeCodexScript = #"""
        #!/bin/sh
        LOG="$0.log"
        THREADS=0
        while IFS= read -r line
        do
          printf '%s\n' "$line" >> "$LOG"
          case "$line" in
            *'"method":"initialize"'*)
              printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
              ;;
            *thread*start*)
              THREADS=$((THREADS + 1))
              if [ "$THREADS" -eq 1 ]; then
                printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"thread":{"id":"thread-one"}}}'
              else
                printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{"thread":{"id":"thread-two"}}}'
              fi
              ;;
          esac
        done
        """#
        try fakeCodexScript.write(to: fakeCodexURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCodexURL.path)

        let client = CodexAppServerClient(
            applicationSupportDirectory: directory,
            codexURLResolver: { fakeCodexURL }
        )
        addTeardownBlock {
            client.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        client.start()
        XCTAssertTrue(waitUntil(timeout: 3) { client.state == .ready })

        client.resetChatSession()
        XCTAssertTrue(waitUntil(timeout: 3) {
            guard let transcript = try? String(contentsOf: transcriptURL, encoding: .utf8) else {
                return false
            }
            return Self.threadStartCount(in: transcript) >= 2
        })
        // The transcript records the restarted thread before the client state
        // flips back; wait for the settled state instead of sampling the gap.
        XCTAssertTrue(waitUntil(timeout: 3) { client.state == .ready })

        let transcript = try String(contentsOf: transcriptURL, encoding: .utf8)
        XCTAssertEqual(Self.threadStartCount(in: transcript), 2)
    }

    func testStartLoginLaunchesBrowserAfterColdServerInitialization() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAppServerClientTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fakeCodexURL = directory.appendingPathComponent("fake-codex")
        let transcriptURL = URL(fileURLWithPath: fakeCodexURL.path + ".log")
        let fakeCodexScript = #"""
        #!/bin/sh
        LOG="$0.log"
        while IFS= read -r line
        do
          printf '%s\n' "$line" >> "$LOG"
          case "$line" in
            *'"method":"initialize"'*)
              printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
              ;;
            *thread*start*)
              printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"thread":{"id":"thread-test"}}}'
              ;;
            *account*login*start*)
              printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{"loginId":"login-test","authUrl":"https://auth.example.test/start"}}'
              ;;
          esac
        done
        """#
        try fakeCodexScript.write(to: fakeCodexURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCodexURL.path)

        let openedAuthURL = expectation(description: "auth URL opened")
        var openedURL: URL?
        let client = CodexAppServerClient(
            applicationSupportDirectory: directory,
            codexURLResolver: { fakeCodexURL },
            openURL: { url in
                openedURL = url
                openedAuthURL.fulfill()
                return true
            }
        )
        addTeardownBlock {
            client.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        client.startLogin()

        wait(for: [openedAuthURL], timeout: 3)
        XCTAssertEqual(openedURL?.absoluteString, "https://auth.example.test/start")
        XCTAssertEqual(client.account, .pending)
        XCTAssertEqual(client.accountDetail, "Finish signing in in your browser…")

        let transcript = try String(contentsOf: transcriptURL, encoding: .utf8)
        XCTAssertTrue(transcript.contains(#""method":"initialize""#))
        XCTAssertTrue(transcript.contains("account"))
        XCTAssertTrue(transcript.contains("login"))
        XCTAssertTrue(transcript.contains("start"))
    }

    func testLoginStartupFailureClearsPendingAccountAndShowsCodexStderr() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAppServerClientTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fakeCodexURL = directory.appendingPathComponent("fake-codex")
        let fakeCodexScript = #"""
        #!/bin/sh
        printf '%s\n' 'env: node: No such file or directory' >&2
        sleep 0.1
        exit 127
        """#
        try fakeCodexScript.write(to: fakeCodexURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeCodexURL.path)

        let client = CodexAppServerClient(
            applicationSupportDirectory: directory,
            codexURLResolver: { fakeCodexURL }
        )
        addTeardownBlock {
            client.stop()
            try? FileManager.default.removeItem(at: directory)
        }

        client.startLogin()

        XCTAssertTrue(waitUntil(timeout: 3) {
            if case .failed = client.state {
                return client.account == .signedOut
            }
            return false
        })
        guard case let .failed(message) = client.state else {
            return XCTFail("Expected failed Codex state")
        }
        XCTAssertTrue(message.contains("Node was not found"), message)
        XCTAssertEqual(client.account, .signedOut)
        XCTAssertTrue(client.accountDetail.contains("Node was not found"), client.accountDetail)
    }

    func testCoachInstructionsUseKGPlannerRoutineBoundary() {
        let instructions = CodexAppServerClient().coachBaseInstructionsForTesting

        XCTAssertTrue(instructions.contains("Momentum - Your Future Coach"))
        XCTAssertTrue(instructions.contains("KGKit planner"))
        XCTAssertTrue(instructions.contains("future-coach-action"))
        XCTAssertTrue(instructions.contains("future-workout-plan"))
        XCTAssertTrue(instructions.contains("future-kg-fact-request"))
        XCTAssertTrue(instructions.contains("\"tool\":\"activate_exercise\""))
        XCTAssertTrue(instructions.contains("\"tool\":\"generate_workout\""))
        XCTAssertTrue(instructions.contains("\"tool\":\"lookup_member_fact\""))
        XCTAssertTrue(instructions.contains("mode \"match_form\""))
        XCTAssertTrue(instructions.contains("\"schemaVersion\":1"))
        XCTAssertFalse(instructions.contains("\"artifactType\":\"routine\""))
        XCTAssertFalse(instructions.contains("```future-routine"))
        XCTAssertTrue(instructions.contains("Do not author brand-new future-exercise artifacts"))
        XCTAssertFalse(instructions.contains("camifit-routine"))
        XCTAssertFalse(instructions.contains("camifit-exercise"))
        XCTAssertFalse(instructions.contains("camifit-kg-operation"))
    }

    func testCoachSupportedExerciseInstructionsMatchGuideReadyGate() {
        let instructions = CodexAppServerClient().coachBaseInstructionsForTesting

        for presetID in AppExerciseTrackingGate.guideReadyPresetIDs {
            XCTAssertTrue(instructions.contains(presetID), "\(presetID) should be chat-activatable")
        }
        for presetID in AppExerciseTrackingGate.referenceCaptureRequiredPresetIDs {
            XCTAssertFalse(instructions.contains(presetID), "\(presetID) must stay out of chat activation")
        }
    }

    private func waitUntil(timeout: TimeInterval, _ condition: @escaping () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    private static func threadStartCount(in transcript: String) -> Int {
        transcript.split(separator: "\n").filter { line in
            line.contains(#""method":"#) && line.contains("thread") && line.contains("start")
        }.count
    }
}
