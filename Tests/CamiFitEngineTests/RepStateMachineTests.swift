import XCTest
@testable import CamiFitEngine

final class RepStateMachineTests: XCTestCase {
    func testSquatPresetStandingDeepStandingSequenceCountsOneRep() throws {
        var harness = try ProductPathHarness()

        let frames = [
            Self.standingFrame(timestampMS: 0)
        ] + Self.deepFrames(startMS: 100, count: 6) + Self.standingFrames(startMS: 700, count: 5)

        let timeline = frames.map { harness.advance(frame: $0) }

        XCTAssertEqual(timeline.last?.repCount, 1)
        XCTAssertEqual(timeline.filter(\.countedThisFrame).count, 1)
        XCTAssertEqual(timeline.last?.phase, .ready)
        XCTAssertTrue(timeline.contains { $0.phase == .down })

        print("rep-state-one-rep \(Self.format(timeline))")
    }

    func testRepeatedStandingAndShallowSequencesDoNotCountFalseReps() throws {
        var standingHarness = try ProductPathHarness()
        let standingTimeline = Self.standingFrames(startMS: 0, count: 6).map { standingHarness.advance(frame: $0) }

        XCTAssertEqual(standingTimeline.last?.repCount, 0)
        XCTAssertFalse(standingTimeline.contains(where: \.countedThisFrame))

        var shallowHarness = try ProductPathHarness()
        let shallowFrames = [Self.standingFrame(timestampMS: 0)] +
            Self.shallowFrames(startMS: 100, count: 6) +
            Self.standingFrames(startMS: 700, count: 5)
        let shallowTimeline = shallowFrames.map { shallowHarness.advance(frame: $0) }

        XCTAssertEqual(shallowTimeline.last?.repCount, 0)
        XCTAssertFalse(shallowTimeline.contains(where: \.countedThisFrame))

        print("rep-state-no-false standing=\(Self.format(standingTimeline)) shallow=\(Self.format(shallowTimeline))")
    }

    func testDeepThenStandingWithoutReadyDoesNotCountFalseRep() throws {
        var harness = try ProductPathHarness()
        let frames = Self.deepFrames(startMS: 0, count: 6) + Self.standingFrames(startMS: 600, count: 5)

        let timeline = frames.map { harness.advance(frame: $0) }

        XCTAssertEqual(timeline.last?.repCount, 0)
        XCTAssertFalse(timeline.contains(where: \.countedThisFrame))
        XCTAssertEqual(timeline.last?.phase, .ready)

        print("rep-state-deep-start \(Self.format(timeline))")
    }

    func testInvalidKneeFrameDoesNotCountAndSurfacesReason() throws {
        var harness = try ProductPathHarness()
        _ = harness.advance(frame: Self.standingFrame(timestampMS: 0))

        let invalidSnapshot = harness.advance(frame: Self.invalidKneeFrame(timestampMS: 100))

        XCTAssertEqual(invalidSnapshot.phase, .ready)
        XCTAssertEqual(invalidSnapshot.repCount, 0)
        XCTAssertFalse(invalidSnapshot.countedThisFrame)
        XCTAssertTrue(invalidSnapshot.invalidReason?.contains("knee") == true)

        print("rep-state-invalid \(invalidSnapshot)")
    }

    private struct ProductPathHarness {
        var processor: FrameSignalProcessor
        let predicateEvaluator: RepPredicateEvaluator
        var stateMachine: RepStateMachine

        init() throws {
            let program = try ProgramLoader.load(from: RepStateMachineTests.presetURL)
            processor = try FrameSignalProcessor(program: program)
            predicateEvaluator = try RepPredicateEvaluator(program: program)
            stateMachine = try RepStateMachine(program: program)
        }

        mutating func advance(frame: PoseFrame) -> RepStateSnapshot {
            let produced = processor.process(frame: frame)
            let down = predicateEvaluator.evaluateDown(producedValues: produced, frame: frame)
            let up = predicateEvaluator.evaluateUp(producedValues: produced, frame: frame)
            return stateMachine.update(downPredicate: down, upPredicate: up)
        }
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

    private static func standingFrames(startMS: Int64, count: Int) -> [PoseFrame] {
        (0 ..< count).map { index in
            standingFrame(timestampMS: startMS + Int64(index * 100))
        }
    }

    private static func deepFrames(startMS: Int64, count: Int) -> [PoseFrame] {
        (0 ..< count).map { index in
            deepSquatFrame(timestampMS: startMS + Int64(index * 100))
        }
    }

    private static func shallowFrames(startMS: Int64, count: Int) -> [PoseFrame] {
        (0 ..< count).map { index in
            shallowSquatFrame(timestampMS: startMS + Int64(index * 100))
        }
    }

    private static func standingFrame(timestampMS: Int64) -> PoseFrame {
        PoseFrame(timestampMS: timestampMS, imageWidth: 1280, imageHeight: 720, landmarks: standingLandmarks)
    }

    private static func deepSquatFrame(timestampMS: Int64) -> PoseFrame {
        PoseFrame(timestampMS: timestampMS, imageWidth: 1280, imageHeight: 720, landmarks: deepSquatLandmarks)
    }

    private static func shallowSquatFrame(timestampMS: Int64) -> PoseFrame {
        PoseFrame(timestampMS: timestampMS, imageWidth: 1280, imageHeight: 720, landmarks: shallowSquatLandmarks)
    }

    private static func invalidKneeFrame(timestampMS: Int64) -> PoseFrame {
        var landmarks = standingLandmarks
        landmarks["primary.knee"] = PoseLandmark(x: 0.65, y: 0.64, z: 0, visibility: 0.2, presence: 1)
        return PoseFrame(timestampMS: timestampMS, imageWidth: 1280, imageHeight: 720, landmarks: landmarks)
    }

    private static var standingLandmarks: [String: PoseLandmark] {
        landmarks(ankleXOffset: 0, ankleYOffset: 0.2)
    }

    private static var deepSquatLandmarks: [String: PoseLandmark] {
        landmarks(ankleXOffset: 0.2, ankleYOffset: 0)
    }

    private static var shallowSquatLandmarks: [String: PoseLandmark] {
        landmarks(ankleXOffset: 0.153, ankleYOffset: 0.129)
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

    private static func format(_ timeline: [RepStateSnapshot]) -> String {
        timeline.enumerated().map { index, snapshot in
            "\(index):\(snapshot.phase.rawValue):reps=\(snapshot.repCount):counted=\(snapshot.countedThisFrame)"
        }.joined(separator: " ")
    }
}
