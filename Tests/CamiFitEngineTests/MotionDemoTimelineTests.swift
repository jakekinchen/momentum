import XCTest
@testable import CamiFitEngine

final class MotionDemoTimelineTests: XCTestCase {
    func testCompilesBundledPresetsIntoPoseFrameTimelines() throws {
        let presetNames = [
            "bodyweight_squat",
            "bodyweight_lunge",
            "bodyweight_pushup",
            "bodyweight_plank"
        ]

        for name in presetNames {
            let program = try ProgramLoader.load(from: Self.presetURL(name))
            let timeline = MotionDemoCompiler.compile(program: program)

            XCTAssertEqual(timeline.programID, program.id)
            XCTAssertEqual(timeline.programName, program.name)
            XCTAssertEqual(timeline.source.current, .proceduralFallback)
            XCTAssertEqual(timeline.source.canonical, .trainerReferenceTrace)
            XCTAssertGreaterThanOrEqual(timeline.frames.count, 8, name)
            XCTAssertGreaterThan(timeline.durationMS, 0, name)

            for frame in timeline.frames {
                for required in program.setup.requiredLandmarks {
                    XCTAssertNotNil(frame.landmark(named: required), "\(name) missing \(required)")
                }
            }

            let looped = timeline.frame(atElapsedMS: timeline.durationMS + 50)
            XCTAssertEqual(looped.timestampMS, 50)
            XCTAssertFalse(looped.landmarks.isEmpty)

            print(
                "motion-demo-timeline preset=\(name) frames=\(timeline.frames.count) " +
                "duration_ms=\(timeline.durationMS) required=\(program.setup.requiredLandmarks.joined(separator: ","))"
            )
        }
    }

    func testSquatDemoTimelineRunsThroughEngineAndCountsOneRep() throws {
        let program = try ProgramLoader.load(from: Self.presetURL("bodyweight_squat"))
        let timeline = MotionDemoCompiler.compile(program: program)
        var recorder = try EngineTraceRecorder(program: program)
        let trace = recorder.record(frames: timeline.frames)
        let counted = trace.filter { $0.rep.countedThisFrame }.map { $0.timestampMS }

        XCTAssertEqual(trace.last?.rep.repCount, 1)
        XCTAssertEqual(counted.count, 1)

        print(
            "motion-demo-squat-engine frames=\(timeline.frames.count) " +
            "final_reps=\(trace.last?.rep.repCount ?? 0) counted=\(counted)"
        )
    }

    func testLungeDemoTimelineKeepsFeetPlantedAndCountsOneRep() throws {
        let program = try ProgramLoader.load(from: Self.presetURL("bodyweight_lunge"))
        let timeline = MotionDemoCompiler.compile(program: program)
        let firstFrame = try XCTUnwrap(timeline.frames.first)
        let contactLandmarks = [
            "primary.heel",
            "primary.foot.index",
            "secondary.foot.index"
        ]
        let supportLandmarks = [
            "secondary.shoulder",
            "secondary.hip",
            "secondary.knee",
            "secondary.ankle",
            "secondary.heel",
            "secondary.foot.index"
        ]
        let anchors = try Dictionary(uniqueKeysWithValues: contactLandmarks.map { name in
            (name, try XCTUnwrap(firstFrame.landmark(named: name), name))
        })

        for frame in timeline.frames {
            for name in supportLandmarks {
                XCTAssertNotNil(frame.landmark(named: name), "\(name) missing at \(frame.timestampMS)ms")
            }
            for name in contactLandmarks {
                let current = try XCTUnwrap(frame.landmark(named: name), name)
                let anchor = try XCTUnwrap(anchors[name], name)
                XCTAssertEqual(current.x, anchor.x, accuracy: 0.000_001, "\(name) x drifted at \(frame.timestampMS)ms")
                XCTAssertEqual(current.y, anchor.y, accuracy: 0.000_001, "\(name) y drifted at \(frame.timestampMS)ms")
            }

            let frontAnkle = try XCTUnwrap(frame.landmark(named: "primary.ankle"))
            let rearAnkle = try XCTUnwrap(frame.landmark(named: "secondary.ankle"))
            let rearHip = try XCTUnwrap(frame.landmark(named: "secondary.hip"))
            let rearKnee = try XCTUnwrap(frame.landmark(named: "secondary.knee"))
            let rearToe = try XCTUnwrap(frame.landmark(named: "secondary.foot.index"))
            let rearHeel = try XCTUnwrap(frame.landmark(named: "secondary.heel"))
            XCTAssertLessThan(rearAnkle.x, frontAnkle.x - 0.35, "rear ankle should stay behind front ankle at \(frame.timestampMS)ms")
            XCTAssertGreaterThan(rearKnee.x, rearAnkle.x, "support knee should stay between rear ankle and hip at \(frame.timestampMS)ms")
            XCTAssertLessThan(rearKnee.x, rearHip.x, "support knee should stay between rear ankle and hip at \(frame.timestampMS)ms")
            XCTAssertLessThan(rearHeel.y, rearToe.y, "rear heel should stay elevated over rear toe at \(frame.timestampMS)ms")
        }

        let firstRearHeel = try XCTUnwrap(firstFrame.landmark(named: "secondary.heel"))
        let deepestRearHeel = try XCTUnwrap(Self.deepestFrame(in: timeline).landmark(named: "secondary.heel"))
        XCTAssertLessThan(
            deepestRearHeel.y,
            firstRearHeel.y - 0.025,
            "rear heel should lift into the bottom position instead of staying statically slanted"
        )

        let deepest = try XCTUnwrap(timeline.frames.min { lhs, rhs in
            Self.kneeAngle(in: lhs) < Self.kneeAngle(in: rhs)
        })
        let deepestFrontKnee = try XCTUnwrap(deepest.landmark(named: "primary.knee"))
        let deepestFrontAnkle = try XCTUnwrap(deepest.landmark(named: "primary.ankle"))
        XCTAssertEqual(
            deepestFrontKnee.x,
            deepestFrontAnkle.x,
            accuracy: 0.04,
            "front knee should stack over planted front ankle at deepest lunge frame"
        )
        XCTAssertLessThan(Self.kneeAngle(in: deepest), 105)

        var recorder = try EngineTraceRecorder(program: program)
        let trace = recorder.record(frames: timeline.frames)
        let counted = trace.filter { $0.rep.countedThisFrame }.map { $0.timestampMS }

        XCTAssertEqual(trace.last?.rep.repCount, 1)
        XCTAssertEqual(counted.count, 1)

        print(
            "motion-demo-lunge-engine frames=\(timeline.frames.count) " +
            "final_reps=\(trace.last?.rep.repCount ?? 0) counted=\(counted)"
        )
    }

    private static func deepestFrame(in timeline: MotionDemoTimeline) throws -> PoseFrame {
        try XCTUnwrap(timeline.frames.min { lhs, rhs in
            Self.kneeAngle(in: lhs) < Self.kneeAngle(in: rhs)
        })
    }

    private static func kneeAngle(in frame: PoseFrame) -> Double {
        guard let hip = frame.landmark(named: "primary.hip"),
              let knee = frame.landmark(named: "primary.knee"),
              let ankle = frame.landmark(named: "primary.ankle") else {
            return .infinity
        }

        let hipVector = (x: hip.x - knee.x, y: hip.y - knee.y)
        let ankleVector = (x: ankle.x - knee.x, y: ankle.y - knee.y)
        let dot = (hipVector.x * ankleVector.x) + (hipVector.y * ankleVector.y)
        let hipMagnitude = sqrt((hipVector.x * hipVector.x) + (hipVector.y * hipVector.y))
        let ankleMagnitude = sqrt((ankleVector.x * ankleVector.x) + (ankleVector.y * ankleVector.y))
        let cosine = min(max(dot / max(hipMagnitude * ankleMagnitude, 0.000_001), -1), 1)
        return acos(cosine) * 180 / .pi
    }

    private static func presetURL(_ name: String) -> URL {
        packageRoot.appendingPathComponent("Presets/\(name).json")
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
