import XCTest
@testable import CamiFitApp

final class PresetMergeTests: XCTestCase {
    func testMergesTwoDirsBundledWinsOnIdCollision() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("camifit-\(UUID().uuidString)")
        let bundled = base.appendingPathComponent("bundled"); let user = base.appendingPathComponent("user")
        try fm.createDirectory(at: bundled, withIntermediateDirectories: true)
        try fm.createDirectory(at: user, withIntermediateDirectories: true)
        let squat = Bundle.module.url(forResource: "bodyweight_squat", withExtension: "json", subdirectory: "Presets")!
        let bundledURL = bundled.appendingPathComponent("bodyweight_squat.json")
        let userURL = user.appendingPathComponent("bodyweight_squat.json")
        try fm.copyItem(at: squat, to: bundledURL)
        try fm.copyItem(at: squat, to: userURL)
        let merged = AppExerciseSessionViewModel.mergedPresetSummaries(from: [bundled, user])
        let summary = try XCTUnwrap(merged.first { $0.id == "bodyweight_squat" })
        XCTAssertEqual(merged.filter { $0.id == "bodyweight_squat" }.count, 1, "no dupes")
        XCTAssertEqual(summary.url.standardizedFileURL.path, bundledURL.standardizedFileURL.path)
    }
}
