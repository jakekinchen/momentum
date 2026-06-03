import XCTest
@testable import CamiFitEngine

final class FilterPipelineTests: XCTestCase {
    func testEMASequenceUsesConfiguredAlpha() throws {
        var pipeline = FilterPipeline(program: filterProgram(filter: SignalFilter(source: "raw", type: .ema, alpha: 0.5)))

        let outputs = [
            pipeline.apply(rawSignals: ["raw": .valid(1, confidence: 1)], timestampMS: 0)["smooth"],
            pipeline.apply(rawSignals: ["raw": .valid(3, confidence: 0.5)], timestampMS: 50)["smooth"],
            pipeline.apply(rawSignals: ["raw": .valid(5, confidence: 1)], timestampMS: 100)["smooth"]
        ]

        XCTAssertValid(outputs[0], equals: 1, accuracy: 0.001)
        XCTAssertValid(outputs[1], equals: 2, accuracy: 0.001)
        XCTAssertValid(outputs[2], equals: 3.5, accuracy: 0.001)
        XCTAssertConfidence(outputs[0], equals: 1, accuracy: 0.001)
        XCTAssertConfidence(outputs[1], equals: 0.75, accuracy: 0.001)
        XCTAssertConfidence(outputs[2], equals: 0.875, accuracy: 0.001)

        print("ema-sequence \(outputs.map { $0!.description }.joined(separator: ","))")
    }

    func testMedianWindowUsesAverageForEvenSampleCount() throws {
        var pipeline = FilterPipeline(program: filterProgram(filter: SignalFilter(source: "raw", type: .median, windowMS: 100)))

        let outputs = [
            pipeline.apply(rawSignals: ["raw": .valid(1, confidence: 0.8)], timestampMS: 0)["smooth"],
            pipeline.apply(rawSignals: ["raw": .valid(5, confidence: 0.6)], timestampMS: 50)["smooth"],
            pipeline.apply(rawSignals: ["raw": .valid(3, confidence: 1)], timestampMS: 100)["smooth"],
            pipeline.apply(rawSignals: ["raw": .valid(9, confidence: 1)], timestampMS: 151)["smooth"]
        ]

        XCTAssertValid(outputs[0], equals: 1, accuracy: 0.001)
        XCTAssertValid(outputs[1], equals: 3, accuracy: 0.001)
        XCTAssertValid(outputs[2], equals: 3, accuracy: 0.001)
        XCTAssertValid(outputs[3], equals: 6, accuracy: 0.001)
        XCTAssertConfidence(outputs[1], equals: 0.6, accuracy: 0.001)

        print("median-window even_policy=average-middle \(outputs.map { $0!.description }.joined(separator: ","))")
    }

    func testInvalidSourceDoesNotCorruptFilterState() throws {
        var pipeline = FilterPipeline(program: filterProgram(filter: SignalFilter(source: "raw", type: .ema, alpha: 0.5)))

        let first = pipeline.apply(rawSignals: ["raw": .valid(10, confidence: 1)], timestampMS: 0)["smooth"]
        let invalid = pipeline.apply(rawSignals: ["raw": .invalid(reason: "low confidence landmark left.knee")], timestampMS: 50)["smooth"]
        let recovered = pipeline.apply(rawSignals: ["raw": .valid(20, confidence: 1)], timestampMS: 100)["smooth"]

        XCTAssertValid(first, equals: 10, accuracy: 0.001)
        XCTAssertInvalid(invalid, contains: "low confidence landmark left.knee")
        XCTAssertValid(recovered, equals: 15, accuracy: 0.001)

        print("invalid-source-output \(invalid!) recovered=\(recovered!)")
    }

    func testFilterPipelineIsDeterministicForSameSequence() throws {
        let program = filterProgram(filter: SignalFilter(source: "raw", type: .ema, alpha: 0.25))
        var first = FilterPipeline(program: program)
        var second = FilterPipeline(program: program)
        let samples: [(Int64, Double)] = [(0, 4), (100, 8), (200, 2)]

        let firstOutputs = samples.map { timestamp, value in
            first.apply(rawSignals: ["raw": .valid(value, confidence: 0.9)], timestampMS: timestamp)
        }
        let secondOutputs = samples.map { timestamp, value in
            second.apply(rawSignals: ["raw": .valid(value, confidence: 0.9)], timestampMS: timestamp)
        }

        XCTAssertEqual(firstOutputs, secondOutputs)
    }

    func testSquatPresetProducedValueTableContainsRawAndFilteredValues() throws {
        let program = try ProgramLoader.load(from: presetURL)
        var processor = try FrameSignalProcessor(program: program)

        let produced = processor.process(frame: standingFrame)

        XCTAssertValid(produced["knee_left"], equals: 180, accuracy: 0.001)
        XCTAssertValid(produced["knee_right"], equals: 180, accuracy: 0.001)
        XCTAssertValid(produced["knee_raw"], equals: 180, accuracy: 0.001)
        XCTAssertValid(produced["torso_raw"], equals: 0, accuracy: 0.001)
        XCTAssertValid(produced["knee_symmetry"], equals: 0, accuracy: 0.001)
        XCTAssertValid(produced["knee"], equals: 180, accuracy: 0.001)
        XCTAssertValid(produced["torso_tilt"], equals: 0, accuracy: 0.001)

        print("produced-squat-table \(stableSignalTable(produced))")
    }

    private func filterProgram(filter: SignalFilter) -> ExerciseProgram {
        ExerciseProgram(
            schemaVersion: 1,
            id: "filter_test",
            name: "Filter Test",
            coordinateSpace: .image2D,
            setup: ProgramSetup(
                requiredView: .side,
                requiredLandmarks: ["primary.hip"],
                minVisibility: 0.65,
                primarySide: .autoLock,
                mirrorHandling: .detect,
                calibration: [:]
            ),
            landmarkAliases: [:],
            signals: ["raw": "1"],
            filters: ["smooth": filter],
            validity: ValidityConfig(
                minSignalConfidence: 0.65,
                phaseSignalInvalidPolicy: .freezeThenReset,
                freezeMS: 500,
                resetAfterMS: 1500
            ),
            rep: RepConfig(
                phaseSignal: "smooth",
                downWhen: "smooth < 1",
                downMinMS: 0,
                bottomMinMS: 0,
                upWhen: "smooth > 1",
                upMinMS: 0,
                minROMDegrees: 1,
                cooldownMS: 0
            ),
            hold: nil,
            formRules: [],
            set: SetConfig(targetReps: 1)
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

    private func XCTAssertConfidence(
        _ value: SignalValue?,
        equals expected: Double,
        accuracy: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .valid(_, confidence) = value else {
            XCTFail("Expected valid value, got \(String(describing: value))", file: file, line: line)
            return
        }

        XCTAssertEqual(confidence, expected, accuracy: accuracy, file: file, line: line)
    }

    private func stableSignalTable(_ values: [String: SignalValue]) -> String {
        values.keys.sorted().map { key in
            "\(key)=\(values[key]!)"
        }.joined(separator: " ")
    }
}
