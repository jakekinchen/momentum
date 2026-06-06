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
        XCTAssertEqual(client.state, .ready)

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

    func testCoachInstructionsUseFutureRoutineArtifactContract() {
        let instructions = CodexAppServerClient().coachBaseInstructionsForTesting

        XCTAssertTrue(instructions.contains("Future Coach"))
        XCTAssertTrue(instructions.contains("future-routine"))
        XCTAssertTrue(instructions.contains("future-coach-action"))
        XCTAssertTrue(instructions.contains("\"tool\":\"activate_exercise\""))
        XCTAssertTrue(instructions.contains("mode \"match_form\""))
        XCTAssertTrue(instructions.contains("\"schemaVersion\":1"))
        XCTAssertTrue(instructions.contains("\"artifactType\":\"routine\""))
        XCTAssertTrue(instructions.contains("Do not author brand-new future-exercise artifacts"))
        XCTAssertFalse(instructions.contains("camifit-routine"))
        XCTAssertFalse(instructions.contains("camifit-exercise"))
        XCTAssertFalse(instructions.contains("camifit-kg-operation"))
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
