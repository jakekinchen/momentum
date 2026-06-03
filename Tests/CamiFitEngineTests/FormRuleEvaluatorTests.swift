import XCTest
@testable import CamiFitEngine

final class FormRuleEvaluatorTests: XCTestCase {
    func testPresetInitializesAllBundledFormRules() throws {
        let program = try ProgramLoader.load(from: Self.presetURL)
        let evaluator = try FormRuleEvaluator(program: program)

        XCTAssertEqual(evaluator.ruleIDs, ["depth", "torso", "symmetry"])

        print("form-rules-preset ids=\(evaluator.ruleIDs.joined(separator: ","))")
    }

    func testDepthRuleEmitsCueAtBottomWhenKneeIsTooHigh() throws {
        let evaluator = try Self.evaluator()

        let snapshots = evaluator.evaluate(
            producedValues: ["knee": .valid(100, confidence: 1)],
            phase: .bottom
        )
        let depth = try XCTUnwrap(snapshots.first { $0.ruleID == "depth" })

        XCTAssertTrue(depth.isActive)
        XCTAssertEqual(depth.expectationPassed, false)
        XCTAssertEqual(depth.cue, "Go deeper")
        XCTAssertEqual(depth.severity, .warn)
        XCTAssertNil(depth.invalidReason)

        print("form-rule-depth-fail \(depth)")
    }

    func testDepthRulePassesAtBottomWhenKneeMeetsExpectation() throws {
        let evaluator = try Self.evaluator()

        let snapshots = evaluator.evaluate(
            producedValues: ["knee": .valid(95, confidence: 1)],
            phase: .bottom
        )
        let depth = try XCTUnwrap(snapshots.first { $0.ruleID == "depth" })

        XCTAssertTrue(depth.isActive)
        XCTAssertEqual(depth.expectationPassed, true)
        XCTAssertNil(depth.cue)
        XCTAssertNil(depth.invalidReason)

        print("form-rule-depth-pass \(depth)")
    }

    func testTorsoRuleIsActiveDuringDescentAndBottomOnly() throws {
        let evaluator = try Self.evaluator()

        let descending = try XCTUnwrap(evaluator.evaluate(
            producedValues: ["torso_tilt": .valid(30, confidence: 1)],
            phase: .descending
        ).first { $0.ruleID == "torso" })
        let bottom = try XCTUnwrap(evaluator.evaluate(
            producedValues: ["torso_tilt": .valid(30, confidence: 1)],
            phase: .bottom
        ).first { $0.ruleID == "torso" })
        let ready = try XCTUnwrap(evaluator.evaluate(
            producedValues: ["torso_tilt": .valid(30, confidence: 1)],
            phase: .ready
        ).first { $0.ruleID == "torso" })

        XCTAssertTrue(descending.isActive)
        XCTAssertEqual(descending.expectationPassed, true)
        XCTAssertTrue(bottom.isActive)
        XCTAssertEqual(bottom.expectationPassed, true)
        XCTAssertFalse(ready.isActive)
        XCTAssertNil(ready.expectationPassed)
        XCTAssertNil(ready.cue)

        print("form-rule-torso descending=\(descending) bottom=\(bottom) ready=\(ready)")
    }

    func testMissingAndInvalidProducedValuesInvalidateRuleWithoutCue() throws {
        let evaluator = try Self.evaluator()

        let missing = try XCTUnwrap(evaluator.evaluate(producedValues: [:], phase: .bottom).first { $0.ruleID == "depth" })
        let invalid = try XCTUnwrap(evaluator.evaluate(
            producedValues: ["knee": .invalid(reason: "low confidence landmark primary.knee")],
            phase: .bottom
        ).first { $0.ruleID == "depth" })

        XCTAssertTrue(missing.isActive)
        XCTAssertNil(missing.expectationPassed)
        XCTAssertNil(missing.cue)
        XCTAssertTrue(missing.invalidReason?.contains("missing signal knee") == true)

        XCTAssertTrue(invalid.isActive)
        XCTAssertNil(invalid.expectationPassed)
        XCTAssertNil(invalid.cue)
        XCTAssertTrue(invalid.invalidReason?.contains("low confidence landmark primary.knee") == true)

        print("form-rule-invalid missing=\(missing) invalid=\(invalid)")
    }

    func testProductPathEvaluatesLoadedFormRulesFromSyntheticFrames() throws {
        var harness = try ProductPathHarness()

        let timeline = Self.validRepFrames(startMS: 0).map { harness.advance(frame: $0) }
        let firstBottom = try XCTUnwrap(timeline.first { entry in
            entry.rep.phase == .bottom && entry.formSnapshots.contains { $0.ruleID == "depth" && $0.isActive }
        })
        let depth = try XCTUnwrap(firstBottom.formSnapshots.first { $0.ruleID == "depth" })

        XCTAssertEqual(firstBottom.rep.phase, .bottom)
        XCTAssertTrue(depth.isActive)
        XCTAssertEqual(depth.expectationPassed, true)
        XCTAssertNil(depth.cue)

        print("form-rule-product-path phase=\(firstBottom.rep.phase.rawValue) \(Self.format(firstBottom.formSnapshots))")
    }

    private struct ProductPathEntry {
        let rep: RepStateSnapshot
        let formSnapshots: [FormRuleSnapshot]
    }

    private struct ProductPathHarness {
        var processor: FrameSignalProcessor
        let predicateEvaluator: RepPredicateEvaluator
        var stateMachine: RepStateMachine
        let formEvaluator: FormRuleEvaluator
        let phaseSignalName: String

        init() throws {
            let program = try ProgramLoader.load(from: FormRuleEvaluatorTests.presetURL)
            let rep = try XCTUnwrap(program.rep)
            processor = try FrameSignalProcessor(program: program)
            predicateEvaluator = try RepPredicateEvaluator(program: program)
            stateMachine = RepStateMachine(rep: rep)
            formEvaluator = try FormRuleEvaluator(program: program)
            phaseSignalName = rep.phaseSignal
        }

        mutating func advance(frame: PoseFrame) -> ProductPathEntry {
            let produced = processor.process(frame: frame)
            let repSnapshot = stateMachine.update(
                timestampMS: frame.timestampMS,
                phaseSignal: produced[phaseSignalName],
                downPredicate: predicateEvaluator.evaluateDown(producedValues: produced, frame: frame),
                upPredicate: predicateEvaluator.evaluateUp(producedValues: produced, frame: frame)
            )
            return ProductPathEntry(
                rep: repSnapshot,
                formSnapshots: formEvaluator.evaluate(producedValues: produced, phase: repSnapshot.phase, frame: frame)
            )
        }
    }

    private static func evaluator() throws -> FormRuleEvaluator {
        try FormRuleEvaluator(program: ProgramLoader.load(from: presetURL))
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static var presetURL: URL {
        packageRoot.appendingPathComponent("Presets/bodyweight_squat.json")
    }

    private static func validRepFrames(startMS: Int64) -> [PoseFrame] {
        [standingFrame(timestampMS: startMS)] +
            deepFrames(startMS: startMS + 100, count: 10) +
            standingFrames(startMS: startMS + 1_100, count: 8)
    }

    private static func standingFrames(startMS: Int64, count: Int, intervalMS: Int64 = 100) -> [PoseFrame] {
        (0 ..< count).map { index in
            standingFrame(timestampMS: startMS + Int64(index) * intervalMS)
        }
    }

    private static func deepFrames(startMS: Int64, count: Int, intervalMS: Int64 = 100) -> [PoseFrame] {
        (0 ..< count).map { index in
            deepSquatFrame(timestampMS: startMS + Int64(index) * intervalMS)
        }
    }

    private static func standingFrame(timestampMS: Int64) -> PoseFrame {
        PoseFrame(timestampMS: timestampMS, imageWidth: 1280, imageHeight: 720, landmarks: standingLandmarks)
    }

    private static func deepSquatFrame(timestampMS: Int64) -> PoseFrame {
        PoseFrame(timestampMS: timestampMS, imageWidth: 1280, imageHeight: 720, landmarks: deepSquatLandmarks)
    }

    private static var standingLandmarks: [String: PoseLandmark] {
        landmarks(ankleXOffset: 0, ankleYOffset: 0.2)
    }

    private static var deepSquatLandmarks: [String: PoseLandmark] {
        landmarks(ankleXOffset: 0.2, ankleYOffset: 0)
    }

    private static func landmarks(ankleXOffset: Double, ankleYOffset: Double) -> [String: PoseLandmark] {
        [
            "left.shoulder": PoseLandmark(x: 0.35, y: 0.24, z: 0, visibility: 1, presence: 1),
            "left.hip": PoseLandmark(x: 0.35, y: 0.44, z: 0, visibility: 1, presence: 1),
            "left.knee": PoseLandmark(x: 0.35, y: 0.64, z: 0, visibility: 1, presence: 1),
            "left.ankle": PoseLandmark(x: 0.35 + ankleXOffset, y: 0.64 + ankleYOffset, z: 0, visibility: 1, presence: 1),
            "right.shoulder": PoseLandmark(x: 0.65, y: 0.24, z: 0, visibility: 1, presence: 1),
            "right.hip": PoseLandmark(x: 0.65, y: 0.44, z: 0, visibility: 1, presence: 1),
            "right.knee": PoseLandmark(x: 0.65, y: 0.64, z: 0, visibility: 1, presence: 1),
            "right.ankle": PoseLandmark(x: 0.65 + ankleXOffset, y: 0.64 + ankleYOffset, z: 0, visibility: 1, presence: 1),
            "primary.shoulder": PoseLandmark(x: 0.65, y: 0.24, z: 0, visibility: 1, presence: 1),
            "primary.hip": PoseLandmark(x: 0.65, y: 0.44, z: 0, visibility: 1, presence: 1),
            "primary.knee": PoseLandmark(x: 0.65, y: 0.64, z: 0, visibility: 1, presence: 1),
            "primary.ankle": PoseLandmark(x: 0.65 + ankleXOffset, y: 0.64 + ankleYOffset, z: 0, visibility: 1, presence: 1)
        ]
    }

    private static func format(_ snapshots: [FormRuleSnapshot]) -> String {
        snapshots.map(\.description).joined(separator: " | ")
    }
}
