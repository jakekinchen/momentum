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

    func testEnvironmentRepoRootWinsOverPackagedHelper() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camifit-env-over-helper-paths-\(UUID().uuidString)")
        let repo = root.appendingPathComponent("repo", isDirectory: true)
        let resources = root.appendingPathComponent("Momentum.app/Contents/Resources", isDirectory: true)
        let helper = root.appendingPathComponent("Momentum.app/Contents/Resources/camifit-pose-worker/camifit-pose-worker")
        let worker = repo.appendingPathComponent("pose_worker/pose_worker.py")
        let python = repo.appendingPathComponent(".venv/bin/python")
        try FileManager.default.createDirectory(at: worker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: python.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: worker, atomically: true, encoding: .utf8)
        try "#!/bin/sh\nexit 0\n".write(to: python, atomically: true, encoding: .utf8)
        try "#!/bin/sh\nexit 0\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = LiveWorkerPaths.resolve(
            environment: ["CAMIFIT_REPO_ROOT": repo.path],
            bundleURL: root.appendingPathComponent("Momentum.app", isDirectory: true),
            resourceURL: resources
        )

        XCTAssertEqual(paths.python.executableURL.path, python.path)
        XCTAssertTrue(paths.python.invokesScript)
        XCTAssertEqual(paths.script.path, worker.path)

        print("live-worker-paths-env-over-helper script=\(paths.script.path)")
    }

    func testPackagedHelperIsPreferredWhenEnvironmentIsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camifit-packaged-helper-paths-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Momentum.app", isDirectory: true)
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        let helper = app.appendingPathComponent("Contents/Resources/camifit-pose-worker/camifit-pose-worker")
        let worker = resources.appendingPathComponent("pose_worker/pose_worker.py")
        let model = resources.appendingPathComponent("pose_worker/models/pose_landmarker_lite.task")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: model.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: helper, atomically: true, encoding: .utf8)
        try "#!/bin/sh\nexit 0\n".write(to: worker, atomically: true, encoding: .utf8)
        try Data().write(to: model)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = LiveWorkerPaths.resolve(
            environment: [:],
            bundleURL: app,
            resourceURL: resources
        )

        XCTAssertEqual(paths.python.executableURL.path, helper.path)
        XCTAssertFalse(paths.python.invokesScript)
        XCTAssertEqual(paths.script.path, helper.path)
        XCTAssertEqual(paths.model.path, model.path)

        print("live-worker-paths-packaged-helper command=\(paths.python.displayName)")
    }

    func testInstalledAppUsesPackagedRepoRootMarkerWhenBundledWorkerIsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camifit-installed-worker-paths-\(UUID().uuidString)")
        let resources = root.appendingPathComponent("AppResources", isDirectory: true)
        let repo = root.appendingPathComponent("repo", isDirectory: true)
        let worker = repo.appendingPathComponent("pose_worker/pose_worker.py")
        let model = repo.appendingPathComponent("pose_worker/models/pose_landmarker_lite.task")
        let python = repo.appendingPathComponent(".venv/bin/python")
        try FileManager.default.createDirectory(
            at: worker.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: model.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: python.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: worker, atomically: true, encoding: .utf8)
        try Data().write(to: model)
        try "#!/bin/sh\nexit 0\n".write(to: python, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
        try repo.path.write(
            to: resources.appendingPathComponent("CamiFitRepoRoot.txt"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = LiveWorkerPaths.resolve(
            environment: [:],
            bundleURL: URL(fileURLWithPath: "/Applications/Momentum.app"),
            resourceURL: resources
        )

        XCTAssertEqual(paths.python.executableURL.path, python.path)
        XCTAssertEqual(paths.script.path, worker.path)
        XCTAssertEqual(paths.model.path, model.path)

        print("live-worker-paths-installed-marker script=\(paths.script.path)")
    }

    func testBundledPoseWorkerWinsOverPackagedRepoRootMarker() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camifit-installed-bundled-worker-paths-\(UUID().uuidString)")
        let resources = root.appendingPathComponent("Resources", isDirectory: true)
        let staleRepo = root.appendingPathComponent("stale-repo", isDirectory: true)
        let bundledWorker = resources.appendingPathComponent("pose_worker/pose_worker.py")
        let bundledModel = resources.appendingPathComponent("pose_worker/models/pose_landmarker_lite.task")
        let staleWorker = staleRepo.appendingPathComponent("pose_worker/pose_worker.py")
        try FileManager.default.createDirectory(
            at: bundledWorker.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: bundledModel.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: staleWorker.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: bundledWorker, atomically: true, encoding: .utf8)
        try Data().write(to: bundledModel)
        try "#!/bin/sh\nexit 0\n".write(to: staleWorker, atomically: true, encoding: .utf8)
        try staleRepo.path.write(
            to: resources.appendingPathComponent("CamiFitRepoRoot.txt"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = LiveWorkerPaths.resolve(
            environment: ["CAMIFIT_PYTHON": "python"],
            bundleURL: URL(fileURLWithPath: "/Applications/Momentum.app"),
            resourceURL: resources
        )

        XCTAssertEqual(paths.script.path, bundledWorker.path)
        XCTAssertEqual(paths.model.path, bundledModel.path)
        XCTAssertFalse(paths.script.path.contains(staleRepo.path))

        print("live-worker-paths-bundled-preferred script=\(paths.script.path)")
    }

    func testDevBundleUsesBundledWorkerWithPackagedRepoVenv() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camifit-dev-bundle-worker-paths-\(UUID().uuidString)")
        let resources = root.appendingPathComponent("Momentum.app/Contents/Resources", isDirectory: true)
        let repo = root.appendingPathComponent("repo", isDirectory: true)
        let bundledWorker = resources.appendingPathComponent("pose_worker/pose_worker.py")
        let bundledModel = resources.appendingPathComponent("pose_worker/models/pose_landmarker_lite.task")
        let repoPython = repo.appendingPathComponent(".venv/bin/python")
        try FileManager.default.createDirectory(
            at: bundledWorker.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: bundledModel.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: repoPython.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: bundledWorker, atomically: true, encoding: .utf8)
        try Data().write(to: bundledModel)
        try "#!/bin/sh\nexit 0\n".write(to: repoPython, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: repoPython.path)
        try repo.path.write(
            to: resources.appendingPathComponent("CamiFitRepoRoot.txt"),
            atomically: true,
            encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = LiveWorkerPaths.resolve(
            environment: [:],
            bundleURL: root.appendingPathComponent("Momentum.app", isDirectory: true),
            resourceURL: resources
        )

        XCTAssertEqual(paths.python.executableURL.path, repoPython.path)
        XCTAssertEqual(paths.script.path, bundledWorker.path)
        XCTAssertEqual(paths.model.path, bundledModel.path)

        print("live-worker-paths-dev-bundle python=\(paths.python.displayName) script=\(paths.script.path)")
    }

    func testBundledPoseWorkerIsFallbackWhenRepoRootMarkerIsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camifit-bundled-worker-paths-\(UUID().uuidString)")
        let resources = root.appendingPathComponent("Resources", isDirectory: true)
        let worker = resources.appendingPathComponent("pose_worker/pose_worker.py")
        try FileManager.default.createDirectory(
            at: worker.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "#!/bin/sh\nexit 0\n".write(to: worker, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = LiveWorkerPaths.resolve(
            environment: ["CAMIFIT_PYTHON": "python"],
            bundleURL: URL(fileURLWithPath: "/Applications/Momentum.app"),
            resourceURL: resources
        )

        XCTAssertEqual(paths.python.executableURL.path, "/usr/bin/env")
        XCTAssertEqual(paths.script.path, worker.path)
        XCTAssertEqual(paths.model.path, resources.appendingPathComponent("pose_worker/models/pose_landmarker_lite.task").path)

        print("live-worker-paths-bundled-fallback script=\(paths.script.path)")
    }

    func testInstalledAppWithoutBundledWorkerDoesNotUseLaunchCurrentDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("camifit-installed-no-current-dir-\(UUID().uuidString)")
        let launchDirectory = root.appendingPathComponent("Documents", isDirectory: true)
        let launchWorker = launchDirectory.appendingPathComponent("pose_worker/pose_worker.py")
        let resources = root.appendingPathComponent("Momentum.app/Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(
            at: launchWorker.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 0\n".write(to: launchWorker, atomically: true, encoding: .utf8)
        let originalDirectory = FileManager.default.currentDirectoryPath
        XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath(launchDirectory.path))
        defer {
            FileManager.default.changeCurrentDirectoryPath(originalDirectory)
            try? FileManager.default.removeItem(at: root)
        }

        let paths = LiveWorkerPaths.resolve(
            environment: ["CAMIFIT_PYTHON": "python"],
            bundleURL: root.appendingPathComponent("Momentum.app", isDirectory: true),
            resourceURL: resources
        )

        XCTAssertEqual(paths.script.path, resources.appendingPathComponent("pose_worker/pose_worker.py").path)
        XCTAssertFalse(paths.script.path.hasPrefix(launchDirectory.path))
        XCTAssertFalse(paths.model.path.hasPrefix(launchDirectory.path))

        print("live-worker-paths-installed-no-current-dir script=\(paths.script.path)")
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

        XCTAssertNotEqual(paths.script.path, "/pose_worker/pose_worker.py")
        XCTAssertFalse(paths.script.path.contains("~/Developer/camifit"))
        XCTAssertFalse(paths.script.path.contains("/Developer/camifit/pose_worker"))

        print("live-worker-paths-default-script=\(paths.script.path)")
    }

    func testRecordingDirectoryLivesInApplicationSupport() {
        let path = LiveSession.defaultRecordDirectory().path

        XCTAssertTrue(path.contains("/Library/Application Support/CamiFit/Capture"))
        XCTAssertFalse(path.contains("/Developer/camifit"))
    }
}
