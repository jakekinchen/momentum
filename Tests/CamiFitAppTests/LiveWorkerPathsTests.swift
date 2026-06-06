import XCTest
@testable import CamiFitApp

final class LiveWorkerPathsTests: XCTestCase {
    func testBarePythonOverrideLaunchesThroughEnvPython3() {
        let paths = LiveWorkerPaths.resolve(environment: [
            "CAMIFIT_REPO_ROOT": "/tmp/camifit-test-repo",
            "CAMIFIT_PYTHON": "python"
        ])

        XCTAssertEqual(paths.python.executableURL.path, "/usr/bin/env")
        XCTAssertEqual(paths.python.argumentsPrefix, ["python3"])
        XCTAssertEqual(paths.script.path, "/tmp/camifit-test-repo/pose_worker/pose_worker.py")

        print("live-worker-paths-python-override command=\(paths.python.displayName)")
    }

    func testProjectLocalVenvIsPreferredWhenNoOverrideIsPresent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camifit-live-worker-paths-\(UUID().uuidString)")
        let python = root.appendingPathComponent(".venv/bin/python")
        try FileManager.default.createDirectory(
            at: python.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: python, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = LiveWorkerPaths.resolve(environment: [
            "CAMIFIT_REPO_ROOT": root.path
        ])

        XCTAssertEqual(paths.python.executableURL.path, python.path)
        XCTAssertEqual(paths.python.argumentsPrefix, [])

        print("live-worker-paths-project-venv command=\(paths.python.displayName)")
    }

    func testPython312CandidatesArePreferredBeforeGenericHomebrewPython3() {
        let repo = URL(fileURLWithPath: "/tmp/camifit-test-repo")
        let home = URL(fileURLWithPath: "/tmp/camifit-test-home")

        let candidates = LiveWorkerPaths.pythonCandidates(repo: repo, home: home).map(\.path)

        XCTAssertEqual(candidates[0], "/tmp/camifit-test-repo/.venv/bin/python")
        XCTAssertEqual(candidates[1], "/tmp/camifit-test-home/.local/bin/python3.12")
        XCTAssertLessThan(
            candidates.firstIndex(of: "/opt/homebrew/bin/python3.12")!,
            candidates.firstIndex(of: "/opt/homebrew/bin/python3")!
        )
    }

    func testDefaultRepoRootDoesNotAssumeDeveloperCamifitPath() {
        let paths = LiveWorkerPaths.resolve(environment: [:])

        XCTAssertFalse(paths.script.path.contains("~/Developer/camifit"))
        XCTAssertFalse(paths.script.path.contains("/Developer/camifit/pose_worker"))

        print("live-worker-paths-default-script=\(paths.script.path)")
    }
}
