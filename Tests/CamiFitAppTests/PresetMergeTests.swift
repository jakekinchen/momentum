import XCTest
@testable import CamiFitApp

final class PresetMergeTests: XCTestCase {
    func testMergesTwoDirsUserWinsOnIdCollision() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("camifit-\(UUID().uuidString)")
        let bundled = base.appendingPathComponent("bundled"); let user = base.appendingPathComponent("user")
        try fm.createDirectory(at: bundled, withIntermediateDirectories: true)
        try fm.createDirectory(at: user, withIntermediateDirectories: true)
        let squat = Bundle.module.url(forResource: "bodyweight_squat", withExtension: "json", subdirectory: "Presets")!
        try fm.copyItem(at: squat, to: bundled.appendingPathComponent("bodyweight_squat.json"))
        try fm.copyItem(at: squat, to: user.appendingPathComponent("bodyweight_squat.json"))
        let merged = AppExerciseSessionViewModel.mergedPresetSummaries(from: [bundled, user])
        XCTAssertEqual(merged.filter { $0.id == "bodyweight_squat" }.count, 1, "user wins, no dupes")
    }
}
