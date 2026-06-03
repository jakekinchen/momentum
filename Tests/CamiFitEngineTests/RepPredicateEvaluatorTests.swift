import XCTest
@testable import CamiFitEngine

final class RepPredicateEvaluatorTests: XCTestCase {
    func testEvaluatesSimpleComparisonOperators() throws {
        let evaluator = try RepPredicateEvaluator(
            downWhen: "knee < 100",
            upWhen: "knee >= 160",
            minSignalConfidence: 0.65
        )

        XCTAssertEqual(evaluator.evaluateDown(producedValues: ["knee": .valid(99, confidence: 1)]), .satisfied)
        XCTAssertEqual(evaluator.evaluateDown(producedValues: ["knee": .valid(100, confidence: 1)]), .unsatisfied)
        XCTAssertEqual(evaluator.evaluateUp(producedValues: ["knee": .valid(160, confidence: 1)]), .satisfied)
        XCTAssertEqual(evaluator.evaluateUp(producedValues: ["knee": .valid(159, confidence: 1)]), .unsatisfied)

        let equality = try RepPredicateEvaluator(
            downWhen: "knee == 90",
            upWhen: "knee != 90",
            minSignalConfidence: 0.65
        )

        XCTAssertEqual(equality.evaluateDown(producedValues: ["knee": .valid(90, confidence: 1)]), .satisfied)
        XCTAssertEqual(equality.evaluateUp(producedValues: ["knee": .valid(90, confidence: 1)]), .unsatisfied)
    }

    func testMissingAndInvalidSignalsReturnInvalidPredicateResults() throws {
        let evaluator = try RepPredicateEvaluator(
            downWhen: "knee < 100",
            upWhen: "knee > 160",
            minSignalConfidence: 0.65
        )

        let missing = evaluator.evaluateDown(producedValues: [:])
        XCTAssertInvalid(missing, contains: "missing signal knee")

        let invalid = evaluator.evaluateUp(producedValues: ["knee": .invalid(reason: "low confidence landmark primary.knee")])
        XCTAssertInvalid(invalid, contains: "signal knee invalid: low confidence landmark primary.knee")

        print("invalid-predicate missing=\(missing) invalid=\(invalid)")
    }

    func testUnsupportedBooleanCompositionFailsClosedAtParseTime() {
        XCTAssertThrowsError(
            try RepPredicateEvaluator(
                downWhen: "knee < 100 and torso_tilt < 20",
                upWhen: "knee > 160",
                minSignalConfidence: 0.65
            )
        ) { error in
            XCTAssertTrue(String(describing: error).contains("expected end of expression"))
        }
    }

    func testSquatPresetPredicatesEvaluateFromFrameSignalProcessorOutput() throws {
        let program = try ProgramLoader.load(from: presetURL)
        let rep = try XCTUnwrap(program.rep)
        var processor = try FrameSignalProcessor(program: program)
        let evaluator = try RepPredicateEvaluator(program: program)

        let standingProduced = processor.process(frame: standingFrame)
        let standingDown = evaluator.evaluateDown(producedValues: standingProduced, frame: standingFrame)
        let standingUp = evaluator.evaluateUp(producedValues: standingProduced, frame: standingFrame)

        var deepProcessor = try FrameSignalProcessor(program: program)
        let deepProduced = deepProcessor.process(frame: deepSquatFrame)
        let deepDown = evaluator.evaluateDown(producedValues: deepProduced, frame: deepSquatFrame)
        let deepUp = evaluator.evaluateUp(producedValues: deepProduced, frame: deepSquatFrame)

        XCTAssertEqual(rep.downWhen, "knee < 100")
        XCTAssertEqual(rep.upWhen, "knee > 160")
        XCTAssertEqual(standingDown, .unsatisfied)
        XCTAssertEqual(standingUp, .satisfied)
        XCTAssertEqual(deepDown, .satisfied)
        XCTAssertEqual(deepUp, .unsatisfied)

        print(
            "rep-predicate-product-path standing down=\(standingDown) up=\(standingUp) knee=\(standingProduced["knee"]!) " +
            "deep down=\(deepDown) up=\(deepUp) knee=\(deepProduced["knee"]!)"
        )
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var presetURL: URL {
        packageRoot.appendingPathComponent("Presets/bodyweight_squat.json")
    }

    private var standingFrame: PoseFrame {
        PoseFrame(timestampMS: 1_000, imageWidth: 1280, imageHeight: 720, landmarks: standingLandmarks)
    }

    private var deepSquatFrame: PoseFrame {
        PoseFrame(timestampMS: 1_000, imageWidth: 1280, imageHeight: 720, landmarks: deepSquatLandmarks)
    }

    private var standingLandmarks: [String: PoseLandmark] {
        [
            "left.shoulder": PoseLandmark(x: 0.35, y: 0.24, z: 0, visibility: 1, presence: 1),
            "left.hip": PoseLandmark(x: 0.35, y: 0.44, z: 0, visibility: 1, presence: 1),
            "left.knee": PoseLandmark(x: 0.35, y: 0.64, z: 0, visibility: 1, presence: 1),
            "left.ankle": PoseLandmark(x: 0.35, y: 0.84, z: 0, visibility: 1, presence: 1),
            "right.shoulder": PoseLandmark(x: 0.65, y: 0.24, z: 0, visibility: 1, presence: 1),
            "right.hip": PoseLandmark(x: 0.65, y: 0.44, z: 0, visibility: 1, presence: 1),
            "right.knee": PoseLandmark(x: 0.65, y: 0.64, z: 0, visibility: 1, presence: 1),
            "right.ankle": PoseLandmark(x: 0.65, y: 0.84, z: 0, visibility: 1, presence: 1),
            "primary.shoulder": PoseLandmark(x: 0.65, y: 0.24, z: 0, visibility: 1, presence: 1),
            "primary.hip": PoseLandmark(x: 0.65, y: 0.44, z: 0, visibility: 1, presence: 1),
            "primary.knee": PoseLandmark(x: 0.65, y: 0.64, z: 0, visibility: 1, presence: 1),
            "primary.ankle": PoseLandmark(x: 0.65, y: 0.84, z: 0, visibility: 1, presence: 1)
        ]
    }

    private var deepSquatLandmarks: [String: PoseLandmark] {
        [
            "left.shoulder": PoseLandmark(x: 0.35, y: 0.24, z: 0, visibility: 1, presence: 1),
            "left.hip": PoseLandmark(x: 0.35, y: 0.44, z: 0, visibility: 1, presence: 1),
            "left.knee": PoseLandmark(x: 0.35, y: 0.64, z: 0, visibility: 1, presence: 1),
            "left.ankle": PoseLandmark(x: 0.55, y: 0.64, z: 0, visibility: 1, presence: 1),
            "right.shoulder": PoseLandmark(x: 0.65, y: 0.24, z: 0, visibility: 1, presence: 1),
            "right.hip": PoseLandmark(x: 0.65, y: 0.44, z: 0, visibility: 1, presence: 1),
            "right.knee": PoseLandmark(x: 0.65, y: 0.64, z: 0, visibility: 1, presence: 1),
            "right.ankle": PoseLandmark(x: 0.85, y: 0.64, z: 0, visibility: 1, presence: 1),
            "primary.shoulder": PoseLandmark(x: 0.65, y: 0.24, z: 0, visibility: 1, presence: 1),
            "primary.hip": PoseLandmark(x: 0.65, y: 0.44, z: 0, visibility: 1, presence: 1),
            "primary.knee": PoseLandmark(x: 0.65, y: 0.64, z: 0, visibility: 1, presence: 1),
            "primary.ankle": PoseLandmark(x: 0.85, y: 0.64, z: 0, visibility: 1, presence: 1)
        ]
    }

    private func XCTAssertInvalid(
        _ value: PredicateResult,
        contains expectedText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .invalid(reason) = value else {
            XCTFail("Expected invalid predicate, got \(value)", file: file, line: line)
            return
        }

        XCTAssertTrue(reason.contains(expectedText), "Expected \(reason) to contain \(expectedText)", file: file, line: line)
    }
}
