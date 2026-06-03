import XCTest
@testable import CamiFitEngine

final class SetProgressTrackerTests: XCTestCase {
    func testPresetInitializesTargetRepsFromSetConfig() throws {
        let program = try ProgramLoader.load(from: Self.presetURL)
        let tracker = SetProgressTracker(program: program)

        XCTAssertEqual(tracker.snapshot.repsCompleted, 0)
        XCTAssertEqual(tracker.snapshot.targetReps, 10)
        XCTAssertFalse(tracker.snapshot.isComplete)

        print("set-progress-preset \(tracker.snapshot)")
    }

    func testCountedRepEventsAdvanceOnceAndIgnoreNonCountedFrames() {
        var tracker = SetProgressTracker(set: SetConfig(targetReps: 3))
        var timeline: [SetProgressSnapshot] = []

        timeline.append(tracker.advance(repSnapshot: Self.repSnapshot(repCount: 0, counted: false)))
        timeline.append(tracker.advance(repSnapshot: Self.repSnapshot(repCount: 1, counted: true)))
        timeline.append(tracker.advance(repSnapshot: Self.repSnapshot(repCount: 1, counted: false)))
        timeline.append(tracker.advance(repSnapshot: Self.repSnapshot(repCount: 2, counted: true)))

        XCTAssertEqual(timeline.map(\.repsCompleted), [0, 1, 1, 2])
        XCTAssertEqual(timeline.map(\.completedThisFrame), [false, false, false, false])
        XCTAssertFalse(timeline.last?.isComplete ?? true)

        print("set-progress-events \(Self.format(timeline))")
    }

    func testCompletionBecomesTrueAtTargetAndRemainsStable() {
        var tracker = SetProgressTracker(set: SetConfig(targetReps: 2))
        var timeline: [SetProgressSnapshot] = []

        timeline.append(tracker.advance(repSnapshot: Self.repSnapshot(repCount: 0, counted: false)))
        timeline.append(tracker.advance(repSnapshot: Self.repSnapshot(repCount: 1, counted: true)))
        timeline.append(tracker.advance(repSnapshot: Self.repSnapshot(repCount: 2, counted: true)))
        timeline.append(tracker.advance(repSnapshot: Self.repSnapshot(repCount: 2, counted: false)))
        timeline.append(tracker.advance(repSnapshot: Self.repSnapshot(repCount: 3, counted: true)))

        XCTAssertEqual(timeline.map(\.repsCompleted), [0, 1, 2, 2, 2])
        XCTAssertEqual(timeline.map(\.isComplete), [false, false, true, true, true])
        XCTAssertEqual(timeline.map(\.completedThisFrame), [false, false, true, false, false])

        print("set-progress-completion \(Self.format(timeline))")
    }

    func testProductPathOneTimedSquatAdvancesSetProgressToOneOfTen() throws {
        var harness = try ProductPathHarness()

        let frames = Self.validRepFrames(startMS: 0)
        let timeline = frames.map { harness.advance(frame: $0) }

        XCTAssertEqual(timeline.last?.repsCompleted, 1)
        XCTAssertEqual(timeline.last?.targetReps, 10)
        XCTAssertFalse(timeline.last?.isComplete ?? true)
        let progressAdvances = zip(timeline, timeline.dropFirst()).filter { previous, current in
            current.repsCompleted > previous.repsCompleted
        }
        XCTAssertEqual(progressAdvances.count, 1)

        print("set-progress-product-path \(Self.format(timeline))")
    }

    private struct ProductPathHarness {
        var processor: FrameSignalProcessor
        let predicateEvaluator: RepPredicateEvaluator
        var stateMachine: RepStateMachine
        var setTracker: SetProgressTracker
        let phaseSignalName: String

        init() throws {
            let program = try ProgramLoader.load(from: SetProgressTrackerTests.presetURL)
            let rep = try XCTUnwrap(program.rep)
            processor = try FrameSignalProcessor(program: program)
            predicateEvaluator = try RepPredicateEvaluator(program: program)
            stateMachine = RepStateMachine(rep: rep)
            setTracker = SetProgressTracker(program: program)
            phaseSignalName = rep.phaseSignal
        }

        mutating func advance(frame: PoseFrame) -> SetProgressSnapshot {
            let produced = processor.process(frame: frame)
            let repSnapshot = stateMachine.update(
                timestampMS: frame.timestampMS,
                phaseSignal: produced[phaseSignalName],
                downPredicate: predicateEvaluator.evaluateDown(producedValues: produced, frame: frame),
                upPredicate: predicateEvaluator.evaluateUp(producedValues: produced, frame: frame)
            )
            return setTracker.advance(repSnapshot: repSnapshot)
        }
    }

    private static func repSnapshot(repCount: Int, counted: Bool) -> RepStateSnapshot {
        RepStateSnapshot(
            phase: .ready,
            repCount: repCount,
            countedThisFrame: counted,
            invalidReason: nil,
            romDegrees: nil,
            cooldownRemainingMS: nil
        )
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

    private static func format(_ timeline: [SetProgressSnapshot]) -> String {
        timeline.enumerated().map { index, snapshot in
            "\(index):reps=\(snapshot.repsCompleted)/\(snapshot.targetReps.map(String.init) ?? "nil"):complete=\(snapshot.isComplete):completed_this_frame=\(snapshot.completedThisFrame)"
        }.joined(separator: " ")
    }
}
