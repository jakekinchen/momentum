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
}
