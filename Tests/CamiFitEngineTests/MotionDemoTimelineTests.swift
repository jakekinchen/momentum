import XCTest
@testable import CamiFitEngine

final class MotionDemoTimelineTests: XCTestCase {
    func testCompilesBundledPresetsIntoPoseFrameTimelines() throws {
        let presetNames = [
            "bodyweight_squat",
            "bodyweight_lunge",
            "bodyweight_pushup",
            "bodyweight_plank",
            "standing_miniband_hip_flexion",
            "resistance_band_reverse_curl",
            "bodyweight_pike",
            "single_arm_dumbbell_preacher_curl",
            "bench_lying_single_arm_dumbbell_tricep_extension",
            "single_arm_cable_tricep_extension",
            "suspension_tricep_press",
            "wide_grip_preacher_curl_with_ez_bar",
            "single_arm_chest_supported_incline_row",
            "machine_chest_supported_row"
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

    func testStandingMinibandHipFlexionDemoTimelineKeepsStanceFootPlantedAndCountsOneRep() throws {
        let program = try ProgramLoader.load(from: Self.presetURL("standing_miniband_hip_flexion"))
        let timeline = MotionDemoCompiler.compile(program: program)
        let firstFrame = try XCTUnwrap(timeline.frames.first)
        let contactLandmarks = [
            "right.heel",
            "right.foot.index"
        ]
        let anchors = try Dictionary(uniqueKeysWithValues: contactLandmarks.map { name in
            (name, try XCTUnwrap(firstFrame.landmark(named: name), name))
        })

        for frame in timeline.frames {
            for name in contactLandmarks {
                let current = try XCTUnwrap(frame.landmark(named: name), name)
                let anchor = try XCTUnwrap(anchors[name], name)
                XCTAssertEqual(current.x, anchor.x, accuracy: 0.000_001, "\(name) x drifted at \(frame.timestampMS)ms")
                XCTAssertEqual(current.y, anchor.y, accuracy: 0.000_001, "\(name) y drifted at \(frame.timestampMS)ms")
            }
        }

        let deepest = try XCTUnwrap(timeline.frames.min { lhs, rhs in
            Self.hipFlexionAngle(in: lhs) < Self.hipFlexionAngle(in: rhs)
        })
        XCTAssertLessThan(Self.hipFlexionAngle(in: deepest), 115)

        var recorder = try EngineTraceRecorder(program: program)
        let trace = recorder.record(frames: timeline.frames)
        let counted = trace.filter { $0.rep.countedThisFrame }.map { $0.timestampMS }

        XCTAssertEqual(trace.last?.rep.repCount, 1)
        XCTAssertEqual(counted.count, 1)

        print(
            "motion-demo-standing-miniband-hip-flexion-engine frames=\(timeline.frames.count) " +
            "final_reps=\(trace.last?.rep.repCount ?? 0) counted=\(counted)"
        )
    }

    func testResistanceBandReverseCurlDemoTimelineCountsOneRep() throws {
        let program = try ProgramLoader.load(from: Self.presetURL("resistance_band_reverse_curl"))
        let timeline = MotionDemoCompiler.compile(program: program)
        let firstFrame = try XCTUnwrap(timeline.frames.first)
        let lastFrame = try XCTUnwrap(timeline.frames.last)
        let firstElbow = Self.elbowAngle(in: firstFrame)
        let lastElbow = Self.elbowAngle(in: lastFrame)
        let deepest = try XCTUnwrap(timeline.frames.min { lhs, rhs in
            Self.elbowAngle(in: lhs) < Self.elbowAngle(in: rhs)
        })

        XCTAssertGreaterThan(firstElbow, 155)
        XCTAssertGreaterThan(lastElbow, 155)
        XCTAssertLessThan(Self.elbowAngle(in: deepest), 85)

        var recorder = try EngineTraceRecorder(program: program)
        let trace = recorder.record(frames: timeline.frames)
        let counted = trace.filter { $0.rep.countedThisFrame }.map { $0.timestampMS }

        XCTAssertEqual(trace.last?.rep.repCount, 1)
        XCTAssertEqual(counted.count, 1)

        print(
            "motion-demo-resistance-band-reverse-curl-engine frames=\(timeline.frames.count) " +
            "elbow=\(Self.elbowAngle(in: deepest))..\(firstElbow) final_reps=\(trace.last?.rep.repCount ?? 0) counted=\(counted)"
        )
    }

    func testSingleArmDumbbellPreacherCurlDemoTimelineCountsOneRep() throws {
        let program = try ProgramLoader.load(from: Self.presetURL("single_arm_dumbbell_preacher_curl"))
        let timeline = MotionDemoCompiler.compile(program: program)
        let firstFrame = try XCTUnwrap(timeline.frames.first)
        let lastFrame = try XCTUnwrap(timeline.frames.last)
        let firstElbow = Self.elbowAngle(in: firstFrame)
        let lastElbow = Self.elbowAngle(in: lastFrame)
        let deepest = try XCTUnwrap(timeline.frames.min { lhs, rhs in
            Self.elbowAngle(in: lhs) < Self.elbowAngle(in: rhs)
        })

        XCTAssertGreaterThan(firstElbow, 155)
        XCTAssertGreaterThan(lastElbow, 155)
        XCTAssertLessThan(Self.elbowAngle(in: deepest), 60)

        var recorder = try EngineTraceRecorder(program: program)
        let trace = recorder.record(frames: timeline.frames)
        let counted = trace.filter { $0.rep.countedThisFrame }.map { $0.timestampMS }

        XCTAssertEqual(trace.last?.rep.repCount, 1)
        XCTAssertEqual(counted.count, 1)

        print(
            "motion-demo-single-arm-dumbbell-preacher-curl-engine frames=\(timeline.frames.count) " +
            "elbow=\(Self.elbowAngle(in: deepest))..\(firstElbow) final_reps=\(trace.last?.rep.repCount ?? 0) counted=\(counted)"
        )
    }

    func testWideGripPreacherCurlWithEZBarDemoTimelineCountsOneRep() throws {
        let program = try ProgramLoader.load(from: Self.presetURL("wide_grip_preacher_curl_with_ez_bar"))
        let timeline = MotionDemoCompiler.compile(program: program)
        let firstFrame = try XCTUnwrap(timeline.frames.first)
        let lastFrame = try XCTUnwrap(timeline.frames.last)
        let firstElbow = Self.elbowAngle(in: firstFrame)
        let lastElbow = Self.elbowAngle(in: lastFrame)
        let deepest = try XCTUnwrap(timeline.frames.min { lhs, rhs in
            Self.elbowAngle(in: lhs) < Self.elbowAngle(in: rhs)
        })

        XCTAssertGreaterThan(firstElbow, 155)
        XCTAssertGreaterThan(lastElbow, 155)
        XCTAssertLessThan(Self.elbowAngle(in: deepest), 60)

        var recorder = try EngineTraceRecorder(program: program)
        let trace = recorder.record(frames: timeline.frames)
        let counted = trace.filter { $0.rep.countedThisFrame }.map { $0.timestampMS }

        XCTAssertEqual(trace.last?.rep.repCount, 1)
        XCTAssertEqual(counted.count, 1)

        print(
            "motion-demo-wide-grip-preacher-curl-ez-bar-engine frames=\(timeline.frames.count) " +
            "elbow=\(Self.elbowAngle(in: deepest))..\(firstElbow) final_reps=\(trace.last?.rep.repCount ?? 0) counted=\(counted)"
        )
    }

    func testSingleArmChestSupportedInclineRowDemoTimelineCountsOneRep() throws {
        let program = try ProgramLoader.load(from: Self.presetURL("single_arm_chest_supported_incline_row"))
        let timeline = MotionDemoCompiler.compile(program: program)
        let firstFrame = try XCTUnwrap(timeline.frames.first)
        let lastFrame = try XCTUnwrap(timeline.frames.last)
        let firstElbow = Self.leftElbowAngle(in: firstFrame)
        let lastElbow = Self.leftElbowAngle(in: lastFrame)
        let deepest = try XCTUnwrap(timeline.frames.min { lhs, rhs in
            Self.leftElbowAngle(in: lhs) < Self.leftElbowAngle(in: rhs)
        })

        XCTAssertGreaterThan(firstElbow, 155)
        XCTAssertGreaterThan(lastElbow, 155)
        XCTAssertLessThan(Self.leftElbowAngle(in: deepest), 95)
        XCTAssertGreaterThan(Self.leftShoulderRowAngle(in: deepest), 45)

        var recorder = try EngineTraceRecorder(program: program)
        let trace = recorder.record(frames: timeline.frames)
        let counted = trace.filter { $0.rep.countedThisFrame }.map { $0.timestampMS }

        XCTAssertEqual(trace.last?.rep.repCount, 1)
        XCTAssertEqual(counted.count, 1)

        print(
            "motion-demo-single-arm-chest-supported-incline-row-engine frames=\(timeline.frames.count) " +
            "elbow=\(Self.leftElbowAngle(in: deepest))..\(firstElbow) shoulder=\(Self.leftShoulderRowAngle(in: deepest)) final_reps=\(trace.last?.rep.repCount ?? 0) counted=\(counted)"
        )
    }

    func testMachineChestSupportedRowDemoTimelineCountsOneRep() throws {
        let program = try ProgramLoader.load(from: Self.presetURL("machine_chest_supported_row"))
        let timeline = MotionDemoCompiler.compile(program: program)
        let firstFrame = try XCTUnwrap(timeline.frames.first)
        let lastFrame = try XCTUnwrap(timeline.frames.last)
        let firstElbow = Self.elbowAngle(in: firstFrame)
        let lastElbow = Self.elbowAngle(in: lastFrame)
        let deepest = try XCTUnwrap(timeline.frames.min { lhs, rhs in
            Self.elbowAngle(in: lhs) < Self.elbowAngle(in: rhs)
        })

        XCTAssertGreaterThan(firstElbow, 155)
        XCTAssertGreaterThan(lastElbow, 155)
        XCTAssertLessThan(Self.elbowAngle(in: deepest), 95)
        XCTAssertGreaterThan(Self.shoulderRowAngle(in: deepest), 45)

        var recorder = try EngineTraceRecorder(program: program)
        let trace = recorder.record(frames: timeline.frames)
        let counted = trace.filter { $0.rep.countedThisFrame }.map { $0.timestampMS }

        XCTAssertEqual(trace.last?.rep.repCount, 1)
        XCTAssertEqual(counted.count, 1)

        print(
            "motion-demo-machine-chest-supported-row-engine frames=\(timeline.frames.count) " +
            "elbow=\(Self.elbowAngle(in: deepest))..\(firstElbow) shoulder=\(Self.shoulderRowAngle(in: deepest)) final_reps=\(trace.last?.rep.repCount ?? 0) counted=\(counted)"
        )
    }

    func testBenchLyingSingleArmDumbbellTricepExtensionDemoTimelineCountsOneRep() throws {
        let program = try ProgramLoader.load(from: Self.presetURL("bench_lying_single_arm_dumbbell_tricep_extension"))
        let timeline = MotionDemoCompiler.compile(program: program)
        let firstFrame = try XCTUnwrap(timeline.frames.first)
        let lastFrame = try XCTUnwrap(timeline.frames.last)
        let firstElbow = Self.elbowAngle(in: firstFrame)
        let lastElbow = Self.elbowAngle(in: lastFrame)
        let deepest = try XCTUnwrap(timeline.frames.min { lhs, rhs in
            Self.elbowAngle(in: lhs) < Self.elbowAngle(in: rhs)
        })

        XCTAssertGreaterThan(firstElbow, 155)
        XCTAssertGreaterThan(lastElbow, 155)
        XCTAssertLessThan(Self.elbowAngle(in: deepest), 90)

        var recorder = try EngineTraceRecorder(program: program)
        let trace = recorder.record(frames: timeline.frames)
        let counted = trace.filter { $0.rep.countedThisFrame }.map { $0.timestampMS }

        XCTAssertEqual(trace.last?.rep.repCount, 1)
        XCTAssertEqual(counted.count, 1)

        print(
            "motion-demo-bench-lying-single-arm-dumbbell-tricep-extension-engine frames=\(timeline.frames.count) " +
            "elbow=\(Self.elbowAngle(in: deepest))..\(firstElbow) final_reps=\(trace.last?.rep.repCount ?? 0) counted=\(counted)"
        )
    }

    func testSingleArmCableTricepExtensionDemoTimelineCountsOneRep() throws {
        let program = try ProgramLoader.load(from: Self.presetURL("single_arm_cable_tricep_extension"))
        let timeline = MotionDemoCompiler.compile(program: program)
        let firstFrame = try XCTUnwrap(timeline.frames.first)
        let lastFrame = try XCTUnwrap(timeline.frames.last)
        let firstElbow = Self.elbowAngle(in: firstFrame)
        let lastElbow = Self.elbowAngle(in: lastFrame)
        let extended = try XCTUnwrap(timeline.frames.max { lhs, rhs in
            Self.elbowAngle(in: lhs) < Self.elbowAngle(in: rhs)
        })

        XCTAssertLessThan(firstElbow, 90)
        XCTAssertLessThan(lastElbow, 90)
        XCTAssertGreaterThan(Self.elbowAngle(in: extended), 150)

        var recorder = try EngineTraceRecorder(program: program)
        let trace = recorder.record(frames: timeline.frames)
        let counted = trace.filter { $0.rep.countedThisFrame }.map { $0.timestampMS }

        XCTAssertEqual(trace.last?.rep.repCount, 1)
        XCTAssertEqual(counted.count, 1)

        print(
            "motion-demo-single-arm-cable-tricep-extension-engine frames=\(timeline.frames.count) " +
            "elbow=\(firstElbow)..\(Self.elbowAngle(in: extended)) final_reps=\(trace.last?.rep.repCount ?? 0) counted=\(counted)"
        )
    }

    func testBodyweightPikeDemoTimelineKeepsHandsAndToesPlantedAndCountsOneRep() throws {
        let program = try ProgramLoader.load(from: Self.presetURL("bodyweight_pike"))
        let timeline = MotionDemoCompiler.compile(program: program)
        let firstFrame = try XCTUnwrap(timeline.frames.first)
        let lastFrame = try XCTUnwrap(timeline.frames.last)
        let contactLandmarks = [
            "primary.wrist",
            "primary.foot.index"
        ]
        let anchors = try Dictionary(uniqueKeysWithValues: contactLandmarks.map { name in
            (name, try XCTUnwrap(firstFrame.landmark(named: name), name))
        })

        for frame in timeline.frames {
            for name in contactLandmarks {
                let current = try XCTUnwrap(frame.landmark(named: name), name)
                let anchor = try XCTUnwrap(anchors[name], name)
                XCTAssertEqual(current.x, anchor.x, accuracy: 0.000_001, "\(name) x drifted at \(frame.timestampMS)ms")
                XCTAssertEqual(current.y, anchor.y, accuracy: 0.000_001, "\(name) y drifted at \(frame.timestampMS)ms")
            }
        }

        let firstPike = Self.pikeAngle(in: firstFrame)
        let lastPike = Self.pikeAngle(in: lastFrame)
        let deepest = try XCTUnwrap(timeline.frames.min { lhs, rhs in
            Self.pikeAngle(in: lhs) < Self.pikeAngle(in: rhs)
        })

        XCTAssertGreaterThan(firstPike, 150)
        XCTAssertGreaterThan(lastPike, 150)
        XCTAssertLessThan(Self.pikeAngle(in: deepest), 85)

        var recorder = try EngineTraceRecorder(program: program)
        let trace = recorder.record(frames: timeline.frames)
        let counted = trace.filter { $0.rep.countedThisFrame }.map { $0.timestampMS }

        XCTAssertEqual(trace.last?.rep.repCount, 1)
        XCTAssertEqual(counted.count, 1)

        print(
            "motion-demo-bodyweight-pike-engine frames=\(timeline.frames.count) " +
            "pike=\(Self.pikeAngle(in: deepest))..\(firstPike) final_reps=\(trace.last?.rep.repCount ?? 0) counted=\(counted)"
        )
    }

    func testSuspensionTricepPressDemoTimelineCountsOneRepAndKeepsBodyLineLong() throws {
        let program = try ProgramLoader.load(from: Self.presetURL("suspension_tricep_press"))
        let timeline = MotionDemoCompiler.compile(program: program)
        let firstFrame = try XCTUnwrap(timeline.frames.first)
        let lastFrame = try XCTUnwrap(timeline.frames.last)
        let firstElbow = Self.elbowAngle(in: firstFrame)
        let lastElbow = Self.elbowAngle(in: lastFrame)
        let extended = try XCTUnwrap(timeline.frames.max { lhs, rhs in
            Self.elbowAngle(in: lhs) < Self.elbowAngle(in: rhs)
        })

        XCTAssertLessThan(firstElbow, 95)
        XCTAssertLessThan(lastElbow, 95)
        XCTAssertGreaterThan(Self.elbowAngle(in: extended), 150)
        for frame in timeline.frames {
            XCTAssertGreaterThan(Self.bodyLineAngle(in: frame), 150)
        }

        var recorder = try EngineTraceRecorder(program: program)
        let trace = recorder.record(frames: timeline.frames)
        let counted = trace.filter { $0.rep.countedThisFrame }.map { $0.timestampMS }

        XCTAssertEqual(trace.last?.rep.repCount, 1)
        XCTAssertEqual(counted.count, 1)

        print(
            "motion-demo-suspension-tricep-press-engine frames=\(timeline.frames.count) " +
            "elbow=\(firstElbow)..\(Self.elbowAngle(in: extended)) final_reps=\(trace.last?.rep.repCount ?? 0) counted=\(counted)"
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

    private static func hipFlexionAngle(in frame: PoseFrame) -> Double {
        guard let shoulder = frame.landmark(named: "left.shoulder"),
              let hip = frame.landmark(named: "left.hip"),
              let knee = frame.landmark(named: "left.knee") else {
            return .infinity
        }

        let shoulderVector = (x: shoulder.x - hip.x, y: shoulder.y - hip.y)
        let kneeVector = (x: knee.x - hip.x, y: knee.y - hip.y)
        let dot = (shoulderVector.x * kneeVector.x) + (shoulderVector.y * kneeVector.y)
        let shoulderMagnitude = sqrt((shoulderVector.x * shoulderVector.x) + (shoulderVector.y * shoulderVector.y))
        let kneeMagnitude = sqrt((kneeVector.x * kneeVector.x) + (kneeVector.y * kneeVector.y))
        let cosine = min(max(dot / max(shoulderMagnitude * kneeMagnitude, 0.000_001), -1), 1)
        return acos(cosine) * 180 / .pi
    }

    private static func elbowAngle(in frame: PoseFrame) -> Double {
        guard let shoulder = frame.landmark(named: "primary.shoulder"),
              let elbow = frame.landmark(named: "primary.elbow"),
              let wrist = frame.landmark(named: "primary.wrist") else {
            return .infinity
        }

        let shoulderVector = (x: shoulder.x - elbow.x, y: shoulder.y - elbow.y)
        let wristVector = (x: wrist.x - elbow.x, y: wrist.y - elbow.y)
        let dot = (shoulderVector.x * wristVector.x) + (shoulderVector.y * wristVector.y)
        let shoulderMagnitude = sqrt((shoulderVector.x * shoulderVector.x) + (shoulderVector.y * shoulderVector.y))
        let wristMagnitude = sqrt((wristVector.x * wristVector.x) + (wristVector.y * wristVector.y))
        let cosine = min(max(dot / max(shoulderMagnitude * wristMagnitude, 0.000_001), -1), 1)
        return acos(cosine) * 180 / .pi
    }

    private static func leftElbowAngle(in frame: PoseFrame) -> Double {
        guard let shoulder = frame.landmark(named: "left.shoulder"),
              let elbow = frame.landmark(named: "left.elbow"),
              let wrist = frame.landmark(named: "left.wrist") else {
            return .infinity
        }

        let shoulderVector = (x: shoulder.x - elbow.x, y: shoulder.y - elbow.y)
        let wristVector = (x: wrist.x - elbow.x, y: wrist.y - elbow.y)
        let dot = (shoulderVector.x * wristVector.x) + (shoulderVector.y * wristVector.y)
        let shoulderMagnitude = sqrt((shoulderVector.x * shoulderVector.x) + (shoulderVector.y * shoulderVector.y))
        let wristMagnitude = sqrt((wristVector.x * wristVector.x) + (wristVector.y * wristVector.y))
        let cosine = min(max(dot / max(shoulderMagnitude * wristMagnitude, 0.000_001), -1), 1)
        return acos(cosine) * 180 / .pi
    }

    private static func leftShoulderRowAngle(in frame: PoseFrame) -> Double {
        guard let elbow = frame.landmark(named: "left.elbow"),
              let shoulder = frame.landmark(named: "left.shoulder"),
              let hip = frame.landmark(named: "left.hip") else {
            return .infinity
        }

        let elbowVector = (x: elbow.x - shoulder.x, y: elbow.y - shoulder.y)
        let hipVector = (x: hip.x - shoulder.x, y: hip.y - shoulder.y)
        let dot = (elbowVector.x * hipVector.x) + (elbowVector.y * hipVector.y)
        let elbowMagnitude = sqrt((elbowVector.x * elbowVector.x) + (elbowVector.y * elbowVector.y))
        let hipMagnitude = sqrt((hipVector.x * hipVector.x) + (hipVector.y * hipVector.y))
        let cosine = min(max(dot / max(elbowMagnitude * hipMagnitude, 0.000_001), -1), 1)
        return acos(cosine) * 180 / .pi
    }

    private static func shoulderRowAngle(in frame: PoseFrame) -> Double {
        guard let elbow = frame.landmark(named: "primary.elbow"),
              let shoulder = frame.landmark(named: "primary.shoulder"),
              let hip = frame.landmark(named: "primary.hip") else {
            return .infinity
        }

        let elbowVector = (x: elbow.x - shoulder.x, y: elbow.y - shoulder.y)
        let hipVector = (x: hip.x - shoulder.x, y: hip.y - shoulder.y)
        let dot = (elbowVector.x * hipVector.x) + (elbowVector.y * hipVector.y)
        let elbowMagnitude = sqrt((elbowVector.x * elbowVector.x) + (elbowVector.y * elbowVector.y))
        let hipMagnitude = sqrt((hipVector.x * hipVector.x) + (hipVector.y * hipVector.y))
        let cosine = min(max(dot / max(elbowMagnitude * hipMagnitude, 0.000_001), -1), 1)
        return acos(cosine) * 180 / .pi
    }

    private static func pikeAngle(in frame: PoseFrame) -> Double {
        guard let shoulder = frame.landmark(named: "primary.shoulder"),
              let hip = frame.landmark(named: "primary.hip"),
              let ankle = frame.landmark(named: "primary.ankle") else {
            return .infinity
        }

        let shoulderVector = (x: shoulder.x - hip.x, y: shoulder.y - hip.y)
        let ankleVector = (x: ankle.x - hip.x, y: ankle.y - hip.y)
        let dot = (shoulderVector.x * ankleVector.x) + (shoulderVector.y * ankleVector.y)
        let shoulderMagnitude = sqrt((shoulderVector.x * shoulderVector.x) + (shoulderVector.y * shoulderVector.y))
        let ankleMagnitude = sqrt((ankleVector.x * ankleVector.x) + (ankleVector.y * ankleVector.y))
        let cosine = min(max(dot / max(shoulderMagnitude * ankleMagnitude, 0.000_001), -1), 1)
        return acos(cosine) * 180 / .pi
    }

    private static func bodyLineAngle(in frame: PoseFrame) -> Double {
        pikeAngle(in: frame)
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
