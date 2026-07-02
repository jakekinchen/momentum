import GLTFKit2
import SceneKit
import XCTest
import CryptoKit
import Foundation
import CamiFitEngine
@testable import CamiFitApp

final class AvatarHumanoidGLBAssetTests: XCTestCase {
    func testNeutralHumanoidGLBLoadsWithRequiredRigNodes() throws {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "neutral_humanoid",
            withExtension: "glb",
            subdirectory: "Avatars"
        ))
        let asset = try GLTFAsset(url: url)
        let source = GLTFSCNSceneSource(asset: asset)
        let root = try XCTUnwrap(source.defaultScene?.rootNode)

        for name in Self.requiredNodeNames {
            XCTAssertNotNil(Self.node(name, in: root), "Missing GLB rig node \(name)")
        }
    }

    func testSquatSceneNormalizationKeepsPlantedFeetStable() throws {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "bodyweight_squat",
            withExtension: "jsonl",
            subdirectory: "MotionDemos"
        ))
        let frames = try MediaPipePoseJSONLDecoder.decode(contentsOf: url)
        let first = try XCTUnwrap(frames.first)
        let movingFrame = try XCTUnwrap(frames.max { lhs, rhs in
            let firstHipY = first.landmarks["primary.hip"]?.y ?? 0
            return abs((lhs.landmarks["primary.hip"]?.y ?? 0) - firstHipY)
                < abs((rhs.landmarks["primary.hip"]?.y ?? 0) - firstHipY)
        })

        let firstPoints = AvatarScenePointNormalizer.normalizedScenePoints(first.landmarks, mirrored: false)
        let movingPoints = AvatarScenePointNormalizer.normalizedScenePoints(movingFrame.landmarks, mirrored: false)
        let firstFootCenter = try Self.footCenter(in: firstPoints, prefix: "primary")
        let movingFootCenter = try Self.footCenter(in: movingPoints, prefix: "primary")
        let firstHip = try XCTUnwrap(firstPoints["primary.hip"])
        let movingHip = try XCTUnwrap(movingPoints["primary.hip"])

        XCTAssertEqual(firstFootCenter.x, movingFootCenter.x, accuracy: 0.000_001)
        XCTAssertEqual(firstFootCenter.y, movingFootCenter.y, accuracy: 0.000_001)
        XCTAssertGreaterThan(abs(movingHip.y - firstHip.y), 0.08)
    }

    func testPikeVisualRigFailurePackagesReviewOnlyMotionDemo() throws {
        XCTAssertNotNil(Bundle.module.url(
            forResource: "bodyweight_pike",
            withExtension: "json",
            subdirectory: "Presets"
        ))
        let motionDemoURL = try XCTUnwrap(Bundle.module.url(
            forResource: "bodyweight_pike",
            withExtension: "jsonl",
            subdirectory: "MotionDemos"
        ))
        let frames = try MediaPipePoseJSONLDecoder.decode(contentsOf: motionDemoURL)
        let manifestURL = try XCTUnwrap(Bundle.module.url(
            forResource: "bodyweight_pike",
            withExtension: "manifest.json",
            subdirectory: "MotionDemos"
        ))
        let manifest = try Self.jsonObject(at: manifestURL)
        let qaGates = try XCTUnwrap(manifest["qa_gates"] as? [String])
        let cleanup = try XCTUnwrap(manifest["review_gallery_motion_cleanup"] as? [String: Any])

        XCTAssertEqual(manifest["acceptance_status"] as? String, "blocked_visual_rig_review_failed")
        XCTAssertEqual(manifest["playable_trace_packaged"] as? Bool, true)
        XCTAssertEqual(manifest["packaging_scope"] as? String, "motion_review_gallery_demo_only")
        XCTAssertTrue(qaGates.contains("visual_rig_review_failed"))
        XCTAssertTrue(qaGates.contains("review_gallery_motion_smoothed"))
        XCTAssertTrue(qaGates.contains("review_gallery_only"))
        XCTAssertEqual(cleanup["status"] as? String, "review_only_smoothed")
        XCTAssertEqual(cleanup["promotion_scope"] as? String, "no guide-ready or validation-ready promotion")
        XCTAssertEqual(frames.count, 117)
        XCTAssertTrue((manifest["visual_review_failure"] as? String)?.contains("detached head/neck") == true)
    }

    func testBodyweightLungeGoldenReferenceHashIsPinned() throws {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "bodyweight_lunge",
            withExtension: "jsonl",
            subdirectory: "MotionDemos"
        ))
        let data = try Data(contentsOf: url)
        let frames = try MediaPipePoseJSONLDecoder.decode(contentsOf: url)

        XCTAssertEqual(Self.sha256Hex(data), Self.approvedBodyweightLungeGoldenSHA256)
        XCTAssertEqual(frames.count, 108)

        let candidateURL = Self.packageRoot
            .appendingPathComponent("dist/motion-reference/bodyweight_lunge/commons_forward_lunge_30_36/bodyweight_lunge.jsonl")
        if FileManager.default.fileExists(atPath: candidateURL.path) {
            XCTAssertNotEqual(try Self.sha256Hex(contentsOf: candidateURL), Self.approvedBodyweightLungeGoldenSHA256)
        }
    }

    func testSquatFrameKeepsUprightHeadAttachment() throws {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "bodyweight_squat",
            withExtension: "jsonl",
            subdirectory: "MotionDemos"
        ))
        let frames = try MediaPipePoseJSONLDecoder.decode(contentsOf: url)
        let first = try XCTUnwrap(frames.first)
        let points = AvatarScenePointNormalizer.normalizedScenePoints(first.landmarks, mirrored: false)
        let axis = try Self.torsoAxis(in: points)

        XCTAssertFalse(AvatarHeadPlacement.isInvertedPose(axis))
        XCTAssertFalse(AvatarHeadPlacement.shouldUseRawAttachment(torsoAxis: axis))
    }

    func testBilateralFootCenteringDoesNotFollowPrimaryOnlyForWideStance() throws {
        let points = AvatarScenePointNormalizer.normalizedScenePoints([
            "left.heel": Self.landmark(0.205, 0.872, -0.05),
            "left.foot.index": Self.landmark(0.355, 0.878, -0.04),
            "right.heel": Self.landmark(0.705, 0.872, 0.05),
            "right.foot.index": Self.landmark(0.855, 0.878, 0.06),
            "primary.heel": Self.landmark(0.705, 0.872, 0.05),
            "primary.foot.index": Self.landmark(0.855, 0.878, 0.06)
        ], mirrored: false)
        let leftFoot = try Self.footCenter(in: points, prefix: "left")
        let rightFoot = try Self.footCenter(in: points, prefix: "right")
        let primaryFoot = try Self.footCenter(in: points, prefix: "primary")
        let bilateralCenterX = (leftFoot.x + rightFoot.x) / 2

        XCTAssertEqual(bilateralCenterX, 0, accuracy: 0.000_001)
        XCTAssertGreaterThan(abs(primaryFoot.x), 0.20)
    }

    func testRejectedJumpingJackBundleDoesNotProduceGuideTimeline() throws {
        XCTAssertNil(Bundle.module.url(
            forResource: "bodyweight_jumping_jack",
            withExtension: "json",
            subdirectory: "Presets"
        ))
        let traceURL = Bundle.module.url(
            forResource: "bodyweight_jumping_jack",
            withExtension: "jsonl",
            subdirectory: "MotionDemos"
        )
        XCTAssertNotNil(Bundle.module.url(
            forResource: "bodyweight_jumping_jack",
            withExtension: "manifest.json",
            subdirectory: "MotionDemos"
        ))
        if let traceURL {
            let manifest = try XCTUnwrap(MotionDemoManifest.load(nextTo: traceURL))
            XCTAssertFalse(manifest.isGuideEligible)
            XCTAssertFalse(manifest.isGuideEligible(for: "bodyweight_jumping_jack"))
        }
        let program = try Self.programWithID("bodyweight_jumping_jack")
        XCTAssertNil(MotionDemoBundleStore.timeline(for: program))
        XCTAssertNil(MotionDemoBundleStore.guideTimeline(for: program))
    }

    func testCaptureRequiredBundlesDoNotProduceGuideTimelines() throws {
        for presetID in Self.captureRequiredPresetIDs {
            let presetURL = try XCTUnwrap(Bundle.module.url(
                forResource: presetID,
                withExtension: "json",
                subdirectory: "Presets"
            ), presetID)
            let traceURL = Bundle.module.url(
                forResource: presetID,
                withExtension: "jsonl",
                subdirectory: "MotionDemos"
            )
            XCTAssertNotNil(Bundle.module.url(
                forResource: presetID,
                withExtension: "manifest.json",
                subdirectory: "MotionDemos"
            ), presetID)
            if let traceURL {
                let manifest = try XCTUnwrap(MotionDemoManifest.load(nextTo: traceURL), presetID)
                XCTAssertFalse(manifest.isGuideEligible, presetID)
                XCTAssertFalse(manifest.isGuideEligible(for: presetID), presetID)
            }
            let program = try ProgramLoader.load(from: presetURL)
            XCTAssertNil(MotionDemoBundleStore.timeline(for: program), presetID)
            XCTAssertNil(MotionDemoBundleStore.guideTimeline(for: program), presetID)
        }
    }

    func testGuideReadyGateMatchesPlayableBundleAndAcceptedManifests() throws {
        let motionDemosURL = try XCTUnwrap(Bundle.module.url(
            forResource: "MotionDemos",
            withExtension: nil
        ))
        let playableIDs = Set(try FileManager.default.contentsOfDirectory(
            at: motionDemosURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "jsonl" }
        .map { $0.deletingPathExtension().lastPathComponent })
        let guideEligibleManifestIDs = Set(try FileManager.default.contentsOfDirectory(
            at: motionDemosURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasSuffix(".manifest.json") }
        .compactMap { url -> String? in
            let traceURL = url.deletingLastPathComponent()
                .appendingPathComponent(url.lastPathComponent.replacingOccurrences(
                    of: ".manifest.json",
                    with: ".jsonl"
                ))
            let presetID = url.lastPathComponent.replacingOccurrences(of: ".manifest.json", with: "")
            return MotionDemoManifest.load(nextTo: traceURL)?.isGuideEligible(for: presetID) == true
                ? url.lastPathComponent.replacingOccurrences(of: ".manifest.json", with: "")
                : nil
        })

        let reviewOnlyPlayableIDs = playableIDs.subtracting(AppExerciseTrackingGate.guideReadyPresetIDs)

        XCTAssertTrue(AppExerciseTrackingGate.guideReadyPresetIDs.isSubset(of: playableIDs))
        XCTAssertTrue(reviewOnlyPlayableIDs.isSubset(of: AppExerciseTrackingGate.referenceCaptureRequiredPresetIDs))
        XCTAssertEqual(guideEligibleManifestIDs, AppExerciseTrackingGate.guideReadyPresetIDs)
        XCTAssertTrue(AppExerciseTrackingGate.guideReadyPresetIDs.isDisjoint(
            with: AppExerciseTrackingGate.referenceCaptureRequiredPresetIDs
        ))

        for presetID in AppExerciseTrackingGate.guideReadyPresetIDs {
            let traceURL = try XCTUnwrap(Bundle.module.url(
                forResource: presetID,
                withExtension: "jsonl",
                subdirectory: "MotionDemos"
            ), presetID)
            let manifest = try XCTUnwrap(MotionDemoManifest.load(nextTo: traceURL), presetID)
            XCTAssertTrue(manifest.isGuideEligible, presetID)
            XCTAssertTrue(manifest.isGuideEligible(for: presetID), presetID)
            let program = try ProgramLoader.load(from: try XCTUnwrap(Bundle.module.url(
                forResource: presetID,
                withExtension: "json",
                subdirectory: "Presets"
            ), presetID))
            XCTAssertNotNil(MotionDemoBundleStore.guideTimeline(for: program), presetID)
        }
    }

    func testMotionDemoManifestFailsClosedWhenMissingOrUnaccepted() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let traceURL = temp.appendingPathComponent("bodyweight_squat.jsonl")
        try "{}\n".write(to: traceURL, atomically: true, encoding: .utf8)

        XCTAssertNil(MotionDemoManifest.load(nextTo: traceURL))

        try "{".write(
            to: temp.appendingPathComponent("bodyweight_squat.manifest.json"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertNil(MotionDemoManifest.load(nextTo: traceURL))

        let unaccepted = MotionDemoManifest(
            sourceKind: .trainerReferenceTrace,
            sourceLabel: "test",
            acceptanceStatus: nil,
            normalizerStatus: nil,
            rejectionReason: nil
        )
        XCTAssertFalse(unaccepted.isGuideEligible)

        let skeletalAccepted = MotionDemoManifest(
            sourceKind: .licensedExternalReferenceTrace,
            sourceLabel: "test",
            acceptanceStatus: "accepted_source_preserving_reference",
            normalizerStatus: nil,
            rejectionReason: nil
        )
        XCTAssertFalse(skeletalAccepted.isGuideEligible)

        let accepted = MotionDemoManifest(
            exerciseID: "test",
            sourceKind: .licensedExternalReferenceTrace,
            sourceLabel: "test",
            acceptanceStatus: "accepted_source_preserving_reference",
            playableTracePackaged: true,
            normalizerStatus: nil,
            rejectionReason: nil,
            sourcePage: "https://example.invalid/source",
            sourceMediaURL: "https://example.invalid/source.mp4",
            sourceVideo: "dist/motion-reference/example/source.mp4",
            sourceLicense: "Test License",
            sourceAttribution: "Test Attribution",
            rawTrace: "dist/motion-reference/example/raw_mediapipe.jsonl",
            normalizer: "scripts/motion_reference/normalize_example_trace.py",
            outputTrace: "dist/motion-reference/example/output.jsonl",
            goldenComparison: MotionDemoManifest.GoldenComparison(
                status: "not_applicable",
                reason: "No protected comparator exists yet.",
                goldenTrace: nil,
                candidateTrace: nil,
                comparisonReport: nil
            ),
            visualReview: MotionDemoManifest.VisualReview(
                status: "passed",
                evidence: "App avatar review passed."
            ),
            engineReplay: MotionDemoManifest.EngineReplay(
                status: "passed",
                test: "MediaPipePoseProviderTests/testGuideReadyMotionDemoTracesDecodeAndReplayThroughEngine",
                actualFinalReps: 1,
                actualHoldTargetReached: nil
            )
        )
        XCTAssertFalse(accepted.isGuideEligible)

        let acceptedWithRejectedSourceReviewButNoLiveAppReview = MotionDemoManifest(
            exerciseID: "test",
            sourceKind: .licensedExternalReferenceTrace,
            sourceLabel: "test",
            acceptanceStatus: "accepted_source_preserving_reference",
            playableTracePackaged: true,
            normalizerStatus: nil,
            rejectionReason: nil,
            sourcePage: "https://example.invalid/source",
            sourceMediaURL: "https://example.invalid/source.mp4",
            sourceVideo: "dist/motion-reference/example/source.mp4",
            sourceLicense: "Test License",
            sourceAttribution: "Test Attribution",
            rawTrace: "dist/motion-reference/example/raw_mediapipe.jsonl",
            normalizer: "scripts/motion_reference/normalize_example_trace.py",
            outputTrace: "dist/motion-reference/example/output.jsonl",
            goldenComparison: MotionDemoManifest.GoldenComparison(
                status: "not_applicable",
                reason: "No protected comparator exists yet.",
                goldenTrace: nil,
                candidateTrace: nil,
                comparisonReport: nil
            ),
            visualReview: MotionDemoManifest.VisualReview(
                status: "passed",
                evidence: "App avatar review passed."
            ),
            engineReplay: MotionDemoManifest.EngineReplay(
                status: "passed",
                test: "MediaPipePoseProviderTests/testGuideReadyMotionDemoTracesDecodeAndReplayThroughEngine",
                actualFinalReps: 1,
                actualHoldTargetReached: nil
            ),
            rejectedSources: MotionDemoManifest.RejectedSources(
                status: "none_retained_for_promotion_review",
                reviewScope: "Unit-test external-source review scope.",
                reason: "No rejected alternatives were retained for this unit-test promotion."
            )
        )
        XCTAssertFalse(acceptedWithRejectedSourceReviewButNoLiveAppReview.isGuideEligible)

        let acceptedWithRejectedSourceReview = MotionDemoManifest(
            exerciseID: "test",
            sourceKind: .licensedExternalReferenceTrace,
            sourceLabel: "test",
            acceptanceStatus: "accepted_source_preserving_reference",
            playableTracePackaged: true,
            normalizerStatus: nil,
            rejectionReason: nil,
            sourcePage: "https://example.invalid/source",
            sourceMediaURL: "https://example.invalid/source.mp4",
            sourceVideo: "dist/motion-reference/example/source.mp4",
            sourceLicense: "Test License",
            sourceAttribution: "Test Attribution",
            rawTrace: "dist/motion-reference/example/raw_mediapipe.jsonl",
            normalizer: "scripts/motion_reference/normalize_example_trace.py",
            outputTrace: "dist/motion-reference/example/output.jsonl",
            goldenComparison: MotionDemoManifest.GoldenComparison(
                status: "not_applicable",
                reason: "No protected comparator exists yet.",
                goldenTrace: nil,
                candidateTrace: nil,
                comparisonReport: nil
            ),
            visualReview: MotionDemoManifest.VisualReview(
                status: "passed",
                evidence: "App avatar review passed."
            ),
            engineReplay: MotionDemoManifest.EngineReplay(
                status: "passed",
                test: "MediaPipePoseProviderTests/testGuideReadyMotionDemoTracesDecodeAndReplayThroughEngine",
                actualFinalReps: 1,
                actualHoldTargetReached: nil
            ),
            liveAppReview: MotionDemoManifest.LiveAppReview(
                status: "passed",
                evidence: "Installed app review passed.",
                appBundle: "/Applications/Momentum.app",
                installedPlayableJSONLs: 1,
                installedPlayableTraceIDs: ["test"]
            ),
            rejectedSources: MotionDemoManifest.RejectedSources(
                status: "none_retained_for_promotion_review",
                reviewScope: "Unit-test external-source review scope.",
                reason: "No rejected alternatives were retained for this unit-test promotion."
            )
        )
        XCTAssertTrue(acceptedWithRejectedSourceReview.isGuideEligible)
        XCTAssertTrue(acceptedWithRejectedSourceReview.isGuideEligible(for: "test"))
        XCTAssertFalse(acceptedWithRejectedSourceReview.isGuideEligible(for: "copied_manifest_wrong_trace"))
        XCTAssertFalse(acceptedWithRejectedSourceReview.isGuideEligible(for: " "))
    }

    func testAuthoredCanonicalManifestGuideEligibility() throws {
        func authoredManifest(liveAppReview: MotionDemoManifest.LiveAppReview?) -> MotionDemoManifest {
            MotionDemoManifest(
                exerciseID: "test",
                sourceKind: .canonicalArchetypeAuthored,
                sourceLabel: "authored keypose timeline",
                acceptanceStatus: "accepted_authored_canonical_reference",
                playableTracePackaged: true,
                normalizerStatus: "implemented",
                rejectionReason: nil,
                sourceLicense: "First-party authored keyposes; no external motion data.",
                sourceAttribution: "CamiFit authored keypose timeline",
                normalizer: "scripts/motion_reference/compile_archetype_trace.py",
                outputTrace: "Sources/CamiFitApp/Resources/MotionDemos/test.jsonl",
                goldenComparison: MotionDemoManifest.GoldenComparison(
                    status: "not_applicable",
                    reason: "Authored canonical trace; no golden comparator applies.",
                    goldenTrace: nil,
                    candidateTrace: nil,
                    comparisonReport: nil
                ),
                visualReview: MotionDemoManifest.VisualReview(
                    status: "passed",
                    evidence: "App avatar review passed."
                ),
                engineReplay: MotionDemoManifest.EngineReplay(
                    status: "passed",
                    test: "MediaPipePoseProviderTests/testGuideReadyMotionDemoTracesDecodeAndReplayThroughEngine",
                    actualFinalReps: 1,
                    actualHoldTargetReached: nil
                ),
                liveAppReview: liveAppReview
            )
        }

        let withoutLiveAppReview = authoredManifest(liveAppReview: nil)
        XCTAssertFalse(withoutLiveAppReview.isGuideEligible)

        let authored = authoredManifest(liveAppReview: MotionDemoManifest.LiveAppReview(
            status: "passed",
            evidence: "Installed app review passed.",
            appBundle: "/Applications/Momentum.app",
            installedPlayableJSONLs: 1,
            installedPlayableTraceIDs: ["test"]
        ))
        XCTAssertTrue(authored.isGuideEligible)
        XCTAssertTrue(authored.isGuideEligible(for: "test"))
        XCTAssertFalse(authored.isGuideEligible(for: "other_exercise"))

        // Candidate (non-authored) canonical traces must stay fail-closed even
        // with complete review evidence.
        let candidate = MotionDemoManifest(
            exerciseID: "test",
            sourceKind: .canonicalArchetypeTrace,
            sourceLabel: "authored keypose timeline",
            acceptanceStatus: "accepted_authored_canonical_reference",
            playableTracePackaged: true,
            normalizerStatus: "implemented",
            rejectionReason: nil,
            sourceLicense: "First-party authored keyposes; no external motion data.",
            sourceAttribution: "CamiFit authored keypose timeline",
            normalizer: "scripts/motion_reference/compile_archetype_trace.py",
            outputTrace: "Sources/CamiFitApp/Resources/MotionDemos/test.jsonl",
            goldenComparison: MotionDemoManifest.GoldenComparison(
                status: "not_applicable",
                reason: "Authored canonical trace; no golden comparator applies.",
                goldenTrace: nil,
                candidateTrace: nil,
                comparisonReport: nil
            ),
            visualReview: MotionDemoManifest.VisualReview(
                status: "passed",
                evidence: "App avatar review passed."
            ),
            engineReplay: MotionDemoManifest.EngineReplay(
                status: "passed",
                test: "MediaPipePoseProviderTests/testGuideReadyMotionDemoTracesDecodeAndReplayThroughEngine",
                actualFinalReps: 1,
                actualHoldTargetReached: nil
            ),
            liveAppReview: MotionDemoManifest.LiveAppReview(
                status: "passed",
                evidence: "Installed app review passed.",
                appBundle: "/Applications/Momentum.app",
                installedPlayableJSONLs: 1,
                installedPlayableTraceIDs: ["test"]
            )
        )
        XCTAssertFalse(candidate.isGuideEligible)
    }

    func testUnlistedProgramDoesNotUseProceduralFallbackAsGuideTimeline() throws {
        let program = try Self.programWithID("future_unreviewed_squat")
        let procedural = MotionDemoCompiler.compile(program: program)

        XCTAssertEqual(procedural.source.current, .proceduralFallback)
        XCTAssertFalse(AppExerciseTrackingGate.guideReadyPresetIDs.contains(program.id))
        XCTAssertNil(MotionDemoBundleStore.timeline(for: program))
        XCTAssertNil(MotionDemoBundleStore.guideTimeline(for: program))
    }

    func testAppSourcesDoNotBypassBundleStoreWithDirectMotionDemoCompilerCalls() throws {
        let appSourcesRoot = Self.packageRoot.appendingPathComponent("Sources/CamiFitApp", isDirectory: true)
        let files = try Self.swiftFiles(under: appSourcesRoot)
        var offenders: [String] = []

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for (offset, line) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                where line.contains("MotionDemoCompiler.compile") {
                offenders.append("\(file.path):\(offset + 1)")
            }
        }

        XCTAssertEqual(offenders, [], "App guide rendering must go through MotionDemoBundleStore and packaged traces.")
    }

    private static func node(_ name: String, in root: SCNNode) -> SCNNode? {
        root.childNode(withName: name, recursively: true)
            ?? root.childNode(withName: name.replacingOccurrences(of: ".", with: "_"), recursively: true)
    }

    private static let captureRequiredPresetIDs = [
        "bench_lying_single_arm_dumbbell_tricep_extension",
        "bodyweight_pike",
        "bodyweight_plank",
        "machine_chest_supported_row",
        "single_arm_chest_supported_incline_row",
        "suspension_tricep_press"
    ]

    private static func programWithID(_ id: String) throws -> ExerciseProgram {
        let squatURL = try XCTUnwrap(Bundle.module.url(
            forResource: "bodyweight_squat",
            withExtension: "json",
            subdirectory: "Presets"
        ))
        let squat = try ProgramLoader.load(from: squatURL)
        return ExerciseProgram(
            schemaVersion: squat.schemaVersion,
            id: id,
            name: "Bodyweight Jumping Jack",
            coordinateSpace: squat.coordinateSpace,
            setup: squat.setup,
            landmarkAliases: squat.landmarkAliases,
            signals: squat.signals,
            filters: squat.filters,
            validity: squat.validity,
            rep: squat.rep,
            hold: squat.hold,
            formRules: squat.formRules,
            set: squat.set
        )
    }

    private static func footCenter(in points: [String: SCNVector3], prefix: String) throws -> SCNVector3 {
        let heel = try XCTUnwrap(points["\(prefix).heel"])
        let toe = try XCTUnwrap(points["\(prefix).foot.index"])
        return SCNVector3(
            (heel.x + toe.x) / 2,
            (heel.y + toe.y) / 2,
            (heel.z + toe.z) / 2
        )
    }

    private static func torsoAxis(in points: [String: SCNVector3]) throws -> SCNVector3 {
        let leftShoulder = try XCTUnwrap(points["left.shoulder"])
        let rightShoulder = try XCTUnwrap(points["right.shoulder"])
        let leftHip = try XCTUnwrap(points["left.hip"])
        let rightHip = try XCTUnwrap(points["right.hip"])
        let shoulderCenter = midpoint(leftShoulder, rightShoulder)
        let hipCenter = midpoint(leftHip, rightHip)
        return SCNVector3(
            hipCenter.x - shoulderCenter.x,
            hipCenter.y - shoulderCenter.y,
            hipCenter.z - shoulderCenter.z
        )
    }

    private static func midpoint(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
        SCNVector3(
            (a.x + b.x) / 2,
            (a.y + b.y) / 2,
            (a.z + b.z) / 2
        )
    }

    private static func distance(_ a: PoseLandmark, _ b: PoseLandmark) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func angle(_ a: PoseLandmark, _ b: PoseLandmark, _ c: PoseLandmark) -> Double {
        let ab = (x: a.x - b.x, y: a.y - b.y)
        let cb = (x: c.x - b.x, y: c.y - b.y)
        let denominator = max(hypot(ab.x, ab.y) * hypot(cb.x, cb.y), 0.000_001)
        let cosine = max(-1, min(1, ((ab.x * cb.x) + (ab.y * cb.y)) / denominator))
        return acos(cosine) * 180 / .pi
    }

    private static func angleToVertical(_ first: PoseLandmark, _ second: PoseLandmark) -> Double {
        let vector = (x: first.x - second.x, y: first.y - second.y)
        let denominator = max(hypot(vector.x, vector.y), 0.000_001)
        let cosine = max(-1, min(1, -vector.y / denominator))
        return acos(cosine) * 180 / .pi
    }

    private static func distance(_ a: SCNVector3, _ b: SCNVector3) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        let dz = a.z - b.z
        return sqrt((dx * dx) + (dy * dy) + (dz * dz))
    }

    private static func maxDelta(from first: PoseFrame, to second: PoseFrame, names: [String]) throws -> Double {
        try names.reduce(0) { current, name in
            let firstPoint = try XCTUnwrap(first.landmark(named: name), name)
            let secondPoint = try XCTUnwrap(second.landmark(named: name), name)
            return max(
                current,
                abs(firstPoint.x - secondPoint.x),
                abs(firstPoint.y - secondPoint.y),
                abs(firstPoint.z - secondPoint.z)
            )
        }
    }

    private static func jsonObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func sha256Hex(contentsOf url: URL) throws -> String {
        try sha256Hex(Data(contentsOf: url))
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func swiftFiles(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.pathExtension == "swift",
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                return nil
            }
            return url
        }
    }

    private static func landmark(_ x: Double, _ y: Double, _ z: Double) -> PoseLandmark {
        PoseLandmark(x: x, y: y, z: z, visibility: 1, presence: 1)
    }

    private static let approvedBodyweightLungeGoldenSHA256 = "04920c88fe91d6bd1c0c218bc8ae04477006bc97a6a1111e458d134f9f3a8a65"

    private static let avatarVisibleJointNames: Set<String> = {
        let sides = ["primary", "secondary", "left", "right"]
        let joints = ["shoulder", "elbow", "wrist", "hip", "knee", "ankle", "heel", "foot.index"]
        return Set(["nose"] + sides.flatMap { side in
            joints.map { "\(side).\($0)" }
        })
    }()

    private static let jumpingJackLimbPairs = [
        ("left.upperArm", "left.shoulder", "left.elbow"),
        ("left.forearm", "left.elbow", "left.wrist"),
        ("right.upperArm", "right.shoulder", "right.elbow"),
        ("right.forearm", "right.elbow", "right.wrist"),
        ("left.thigh", "left.hip", "left.knee"),
        ("left.shin", "left.knee", "left.ankle"),
        ("right.thigh", "right.hip", "right.knee"),
        ("right.shin", "right.knee", "right.ankle")
    ]

    private static let jumpingJackMotionJointNames = [
        "nose",
        "left.shoulder", "left.elbow", "left.wrist", "left.hip", "left.knee", "left.ankle",
        "right.shoulder", "right.elbow", "right.wrist", "right.hip", "right.knee", "right.ankle",
        "left.heel", "left.foot.index", "right.heel", "right.foot.index"
    ]

    private static let requiredNodeNames = [
        "avatar.head",
        "avatar.neck",
        "avatar.chest",
        "avatar.spine",
        "avatar.abdomen",
        "avatar.pelvis",
        "avatar.shoulderBridge",
        "avatar.hipBridge",
        "avatar.near.upperArm",
        "avatar.near.forearm",
        "avatar.far.upperArm",
        "avatar.far.forearm",
        "avatar.near.upperLeg",
        "avatar.near.lowerLeg",
        "avatar.far.upperLeg",
        "avatar.far.lowerLeg",
        "avatar.near.foot",
        "avatar.far.foot",
        "avatar.near.hand",
        "avatar.far.hand",
        "avatar.near.elbow",
        "avatar.far.elbow",
        "avatar.near.knee",
        "avatar.far.knee",
        "avatar.near.ankle",
        "avatar.far.ankle",
    ]
}
