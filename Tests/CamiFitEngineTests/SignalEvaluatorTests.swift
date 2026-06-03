import XCTest
@testable import CamiFitEngine

final class SignalEvaluatorTests: XCTestCase {
    func testEvaluatesSquatPresetSignalsFromSyntheticStandingPose() throws {
        let program = try ProgramLoader.load(from: presetURL)
        let evaluator = try SignalEvaluator(program: program)

        let values = evaluator.evaluateSignals(frame: standingFrame)

        XCTAssertValid(values["knee_left"], equals: 180, accuracy: 0.001)
        XCTAssertValid(values["knee_right"], equals: 180, accuracy: 0.001)
        XCTAssertValid(values["knee_raw"], equals: 180, accuracy: 0.001)
        XCTAssertValid(values["torso_raw"], equals: 0, accuracy: 0.001)
        XCTAssertValid(values["knee_symmetry"], equals: 0, accuracy: 0.001)

        print("evaluated-squat-signals \(stableSignalTable(values))")
    }

    func testLowVisibilityInvalidatesOnlyDependentSignals() throws {
        let program = try ProgramLoader.load(from: presetURL)
        let evaluator = try SignalEvaluator(program: program)
        var landmarks = standingLandmarks
        landmarks["left.knee"] = PoseLandmark(x: 0.35, y: 0.64, z: 0, visibility: 0.2, presence: 1.0)

        let values = evaluator.evaluateSignals(frame: PoseFrame(timestampMS: 1_000, imageWidth: 1280, imageHeight: 720, landmarks: landmarks))

        XCTAssertInvalid(values["knee_left"], contains: "left.knee")
        XCTAssertInvalid(values["knee_symmetry"], contains: "left.knee")
        XCTAssertValid(values["knee_right"], equals: 180, accuracy: 0.001)
        XCTAssertValid(values["knee_raw"], equals: 180, accuracy: 0.001)

        print("low-visibility-reason \(invalidReason(values["knee_left"]))")
    }

    func testSafeDivideAndDegenerateAngleReturnInvalid() throws {
        let evaluator = try SignalEvaluator(program: ProgramLoader.load(from: presetURL))

        let divideByZero = evaluator.evaluateExpression("10 / 0", frame: standingFrame)
        XCTAssertInvalid(divideByZero, contains: "divide by zero")

        let degenerateAngle = evaluator.evaluateExpression("angle(left.knee, left.knee, left.ankle)", frame: standingFrame)
        XCTAssertInvalid(degenerateAngle, contains: "degenerate angle")

        print("invalid-arithmetic \(divideByZero) \(degenerateAngle)")
    }

    func testEvaluationIsDeterministic() throws {
        let program = try ProgramLoader.load(from: presetURL)
        let evaluator = try SignalEvaluator(program: program)

        let first = evaluator.evaluateSignals(frame: standingFrame)
        let second = evaluator.evaluateSignals(frame: standingFrame)

        XCTAssertEqual(first, second)
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

    private func XCTAssertValid(
        _ value: SignalValue?,
        equals expected: Double,
        accuracy: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .valid(actual, _) = value else {
            XCTFail("Expected valid value, got \(String(describing: value))", file: file, line: line)
            return
        }

        XCTAssertEqual(actual, expected, accuracy: accuracy, file: file, line: line)
    }

    private func XCTAssertInvalid(
        _ value: SignalValue?,
        contains expectedText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .invalid(reason) = value else {
            XCTFail("Expected invalid value, got \(String(describing: value))", file: file, line: line)
            return
        }

        XCTAssertTrue(reason.contains(expectedText), "Expected \(reason) to contain \(expectedText)", file: file, line: line)
    }

    private func invalidReason(_ value: SignalValue?) -> String {
        guard case let .invalid(reason) = value else {
            return String(describing: value)
        }

        return reason
    }

    private func stableSignalTable(_ values: [String: SignalValue]) -> String {
        values.keys.sorted().map { key in
            "\(key)=\(values[key]!)"
        }.joined(separator: " ")
    }
}
