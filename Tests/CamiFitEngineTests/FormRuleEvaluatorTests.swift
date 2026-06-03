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
        var evaluator = try Self.evaluator()

        let snapshots = evaluator.update(
            timestampMS: 0,
            producedValues: ["knee": .valid(100, confidence: 1)],
            phase: .bottom
        )
        let depth = try XCTUnwrap(snapshots.first { $0.ruleID == "depth" })

        XCTAssertTrue(depth.isActive)
        XCTAssertEqual(depth.expectationPassed, false)
        XCTAssertEqual(depth.cue, "Go deeper")
        XCTAssertEqual(depth.severity, .warn)
        XCTAssertEqual(depth.violationDurationMS, 0)
        XCTAssertNil(depth.invalidReason)

        print("form-rule-depth-fail \(depth)")
    }

    func testTorsoRuleCuesOnlyAfterMinViolationDuration() throws {
        var evaluator = try Self.evaluator()

        let first = try XCTUnwrap(evaluator.update(
            timestampMS: 0,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        ).first { $0.ruleID == "torso" })
        let early = try XCTUnwrap(evaluator.update(
            timestampMS: 100,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        ).first { $0.ruleID == "torso" })
        let ready = try XCTUnwrap(evaluator.update(
            timestampMS: 250,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        ).first { $0.ruleID == "torso" })

        XCTAssertEqual(first.expectationPassed, false)
        XCTAssertEqual(first.violationDurationMS, 0)
        XCTAssertNil(first.cue)
        XCTAssertEqual(early.expectationPassed, false)
        XCTAssertEqual(early.violationDurationMS, 100)
        XCTAssertNil(early.cue)
        XCTAssertEqual(ready.expectationPassed, false)
        XCTAssertEqual(ready.violationDurationMS, 250)
        XCTAssertEqual(ready.cue, "Chest up")

        print("form-rule-torso-timing first=\(first) early=\(early) ready=\(ready)")
    }

    func testTorsoRuleSuppressesRepeatCueUntilCooldownElapses() throws {
        var evaluator = try Self.evaluator()

        _ = evaluator.update(
            timestampMS: 0,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        )
        let firstCue = try XCTUnwrap(evaluator.update(
            timestampMS: 250,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        ).first { $0.ruleID == "torso" })
        let suppressed = try XCTUnwrap(evaluator.update(
            timestampMS: 500,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        ).first { $0.ruleID == "torso" })
        let secondCue = try XCTUnwrap(evaluator.update(
            timestampMS: 1_750,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        ).first { $0.ruleID == "torso" })

        XCTAssertEqual(firstCue.cue, "Chest up")
        XCTAssertEqual(firstCue.cueCooldownRemainingMS, 1_500)
        XCTAssertEqual(suppressed.expectationPassed, false)
        XCTAssertNil(suppressed.cue)
        XCTAssertEqual(suppressed.violationDurationMS, 500)
        XCTAssertEqual(suppressed.cueCooldownRemainingMS, 1_250)
        XCTAssertEqual(secondCue.cue, "Chest up")
        XCTAssertEqual(secondCue.violationDurationMS, 1_750)
        XCTAssertEqual(secondCue.cueCooldownRemainingMS, 1_500)

        print("form-rule-cooldown first=\(firstCue) suppressed=\(suppressed) second=\(secondCue)")
    }

    func testPassingInactiveAndInvalidFramesDoNotBreakLaterEligibleCue() throws {
        var passingReset = try Self.evaluator()
        _ = passingReset.update(
            timestampMS: 0,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        )
        _ = passingReset.update(
            timestampMS: 250,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        )
        let passing = try XCTUnwrap(passingReset.update(
            timestampMS: 500,
            producedValues: ["torso_tilt": .valid(30, confidence: 1)],
            phase: .descending
        ).first { $0.ruleID == "torso" })
        let passingRestart = try XCTUnwrap(passingReset.update(
            timestampMS: 1_800,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        ).first { $0.ruleID == "torso" })
        let passingCue = try XCTUnwrap(passingReset.update(
            timestampMS: 2_050,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        ).first { $0.ruleID == "torso" })

        var inactiveReset = try Self.evaluator()
        _ = inactiveReset.update(
            timestampMS: 0,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        )
        _ = inactiveReset.update(
            timestampMS: 250,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        )
        let inactive = try XCTUnwrap(inactiveReset.update(
            timestampMS: 500,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .ready
        ).first { $0.ruleID == "torso" })
        let inactiveRestart = try XCTUnwrap(inactiveReset.update(
            timestampMS: 1_800,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        ).first { $0.ruleID == "torso" })
        let inactiveCue = try XCTUnwrap(inactiveReset.update(
            timestampMS: 2_050,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        ).first { $0.ruleID == "torso" })

        var invalidReset = try Self.evaluator()
        _ = invalidReset.update(
            timestampMS: 0,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        )
        _ = invalidReset.update(
            timestampMS: 250,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        )
        let invalid = try XCTUnwrap(invalidReset.update(
            timestampMS: 500,
            producedValues: ["torso_tilt": .invalid(reason: "low confidence torso")],
            phase: .descending
        ).first { $0.ruleID == "torso" })
        let invalidRestart = try XCTUnwrap(invalidReset.update(
            timestampMS: 1_800,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        ).first { $0.ruleID == "torso" })
        let invalidCue = try XCTUnwrap(invalidReset.update(
            timestampMS: 2_050,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        ).first { $0.ruleID == "torso" })

        XCTAssertEqual(passing.expectationPassed, true)
        XCTAssertNil(passing.cue)
        XCTAssertEqual(passingRestart.violationDurationMS, 0)
        XCTAssertNil(passingRestart.cue)
        XCTAssertEqual(passingCue.cue, "Chest up")

        XCTAssertFalse(inactive.isActive)
        XCTAssertNil(inactive.cue)
        XCTAssertEqual(inactiveRestart.violationDurationMS, 0)
        XCTAssertNil(inactiveRestart.cue)
        XCTAssertEqual(inactiveCue.cue, "Chest up")

        XCTAssertNil(invalid.expectationPassed)
        XCTAssertNil(invalid.cue)
        XCTAssertEqual(invalidRestart.violationDurationMS, 0)
        XCTAssertNil(invalidRestart.cue)
        XCTAssertEqual(invalidCue.cue, "Chest up")

        print("form-rule-cooldown-reset passing=\(passingCue) inactive=\(inactiveCue) invalid=\(invalidCue)")
    }

    func testPassingInactiveAndInvalidFramesResetViolationTimer() throws {
        var passingReset = try Self.evaluator()
        let first = try XCTUnwrap(passingReset.update(
            timestampMS: 0,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        ).first { $0.ruleID == "torso" })
        let passing = try XCTUnwrap(passingReset.update(
            timestampMS: 300,
            producedValues: ["torso_tilt": .valid(30, confidence: 1)],
            phase: .descending
        ).first { $0.ruleID == "torso" })
        let afterPassing = try XCTUnwrap(passingReset.update(
            timestampMS: 500,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        ).first { $0.ruleID == "torso" })

        var inactiveReset = try Self.evaluator()
        _ = inactiveReset.update(
            timestampMS: 0,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        )
        let inactive = try XCTUnwrap(inactiveReset.update(
            timestampMS: 300,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .ready
        ).first { $0.ruleID == "torso" })
        let afterInactive = try XCTUnwrap(inactiveReset.update(
            timestampMS: 500,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        ).first { $0.ruleID == "torso" })

        var invalidReset = try Self.evaluator()
        _ = invalidReset.update(
            timestampMS: 0,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        )
        let invalid = try XCTUnwrap(invalidReset.update(
            timestampMS: 300,
            producedValues: ["torso_tilt": .invalid(reason: "low confidence torso")],
            phase: .descending
        ).first { $0.ruleID == "torso" })
        let afterInvalid = try XCTUnwrap(invalidReset.update(
            timestampMS: 500,
            producedValues: ["torso_tilt": .valid(50, confidence: 1)],
            phase: .descending
        ).first { $0.ruleID == "torso" })

        XCTAssertEqual(first.violationDurationMS, 0)
        XCTAssertEqual(passing.expectationPassed, true)
        XCTAssertNil(passing.violationDurationMS)
        XCTAssertEqual(afterPassing.expectationPassed, false)
        XCTAssertEqual(afterPassing.violationDurationMS, 0)
        XCTAssertNil(afterPassing.cue)

        XCTAssertFalse(inactive.isActive)
        XCTAssertNil(inactive.violationDurationMS)
        XCTAssertEqual(afterInactive.expectationPassed, false)
        XCTAssertEqual(afterInactive.violationDurationMS, 0)
        XCTAssertNil(afterInactive.cue)

        XCTAssertNil(invalid.expectationPassed)
        XCTAssertNil(invalid.violationDurationMS)
        XCTAssertEqual(afterInvalid.expectationPassed, false)
        XCTAssertEqual(afterInvalid.violationDurationMS, 0)
        XCTAssertNil(afterInvalid.cue)

        print("form-rule-reset passing=\(afterPassing) inactive=\(afterInactive) invalid=\(afterInvalid)")
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

    func testScoreSummaryGivesFullCreditForPassingActiveRules() throws {
        let summarizer = try Self.summarizer()
        let summary = summarizer.summarize([
            Self.snapshot(ruleID: "depth", isActive: true, expectationPassed: true, severity: .warn),
            Self.snapshot(ruleID: "torso", isActive: true, expectationPassed: true, severity: .warn),
            Self.snapshot(ruleID: "symmetry", isActive: true, expectationPassed: true, severity: .info)
        ])

        XCTAssertEqual(summary.score, 1.0)
        XCTAssertEqual(summary.earnedWeight, 22)
        XCTAssertEqual(summary.possibleWeight, 22)
        XCTAssertEqual(summary.activeRuleCount, 3)
        XCTAssertEqual(summary.scoredRuleCount, 3)
        XCTAssertEqual(summary.invalidActiveRuleCount, 0)
        XCTAssertNil(summary.selectedCue)

        print("form-rule-score-full \(summary)")
    }

    func testScoreSummaryPenalizesFailedActiveRulesByWeight() throws {
        let summarizer = try Self.summarizer()
        let summary = summarizer.summarize([
            Self.snapshot(ruleID: "depth", isActive: true, expectationPassed: true, severity: .warn),
            Self.snapshot(ruleID: "torso", isActive: true, expectationPassed: false, cue: "Chest up", severity: .warn),
            Self.snapshot(ruleID: "symmetry", isActive: true, expectationPassed: true, severity: .info)
        ])

        XCTAssertEqual(try XCTUnwrap(summary.score), 14.0 / 22.0, accuracy: 0.000_001)
        XCTAssertEqual(summary.earnedWeight, 14)
        XCTAssertEqual(summary.possibleWeight, 22)
        XCTAssertEqual(summary.selectedCueRuleID, "torso")
        XCTAssertEqual(summary.selectedCue, "Chest up")

        print("form-rule-score-weighted-fail \(summary)")
    }

    func testScoreSummaryExcludesInactiveAndInvalidRulesFromDenominator() throws {
        let summarizer = try Self.summarizer()
        let summary = summarizer.summarize([
            Self.snapshot(ruleID: "depth", isActive: true, expectationPassed: true, severity: .warn),
            Self.snapshot(ruleID: "torso", isActive: false, expectationPassed: nil, severity: .warn),
            Self.snapshot(
                ruleID: "symmetry",
                isActive: true,
                expectationPassed: nil,
                severity: .info,
                invalidReason: "low confidence knee_symmetry"
            )
        ])

        XCTAssertEqual(summary.score, 1.0)
        XCTAssertEqual(summary.earnedWeight, 10)
        XCTAssertEqual(summary.possibleWeight, 10)
        XCTAssertEqual(summary.activeRuleCount, 2)
        XCTAssertEqual(summary.scoredRuleCount, 1)
        XCTAssertEqual(summary.invalidActiveRuleCount, 1)

        print("form-rule-score-invalid-policy \(summary)")
    }

    func testScoreSummarySelectsCueBySeverityWeightThenProgramOrder() throws {
        let summarizer = try Self.summarizer()
        let severitySummary = summarizer.summarize([
            Self.snapshot(ruleID: "depth", isActive: true, expectationPassed: false, cue: "Go deeper", severity: .warn),
            Self.snapshot(ruleID: "symmetry", isActive: true, expectationPassed: false, cue: "Even both sides", severity: .fail)
        ])
        let weightSummary = summarizer.summarize([
            Self.snapshot(ruleID: "torso", isActive: true, expectationPassed: false, cue: "Chest up", severity: .warn),
            Self.snapshot(ruleID: "depth", isActive: true, expectationPassed: false, cue: "Go deeper", severity: .warn)
        ])
        let orderSummary = try FormRuleScoreSummarizer(program: Self.programWithEqualWeightRules()).summarize([
            Self.snapshot(ruleID: "second", isActive: true, expectationPassed: false, cue: "Second cue", severity: .warn),
            Self.snapshot(ruleID: "first", isActive: true, expectationPassed: false, cue: "First cue", severity: .warn)
        ])

        XCTAssertEqual(severitySummary.selectedCueRuleID, "symmetry")
        XCTAssertEqual(severitySummary.selectedCue, "Even both sides")
        XCTAssertEqual(weightSummary.selectedCueRuleID, "depth")
        XCTAssertEqual(weightSummary.selectedCue, "Go deeper")
        XCTAssertEqual(orderSummary.selectedCueRuleID, "first")
        XCTAssertEqual(orderSummary.selectedCue, "First cue")

        print("form-rule-score-cue-priority severity=\(severitySummary) weight=\(weightSummary) order=\(orderSummary)")
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
        XCTAssertEqual(firstBottom.formSummary.score, 1.0)
        XCTAssertEqual(firstBottom.formSummary.earnedWeight, 22)
        XCTAssertEqual(firstBottom.formSummary.possibleWeight, 22)
        XCTAssertNil(firstBottom.formSummary.selectedCue)

        print("form-rule-product-path phase=\(firstBottom.rep.phase.rawValue) \(Self.format(firstBottom.formSnapshots)) summary=\(firstBottom.formSummary)")
    }

    private struct ProductPathEntry {
        let rep: RepStateSnapshot
        let formSnapshots: [FormRuleSnapshot]
        let formSummary: FormRuleScoreSummary
    }

    private struct ProductPathHarness {
        var processor: FrameSignalProcessor
        let predicateEvaluator: RepPredicateEvaluator
        var stateMachine: RepStateMachine
        var formEvaluator: FormRuleEvaluator
        let formSummarizer: FormRuleScoreSummarizer
        let phaseSignalName: String

        init() throws {
            let program = try ProgramLoader.load(from: FormRuleEvaluatorTests.presetURL)
            let rep = try XCTUnwrap(program.rep)
            processor = try FrameSignalProcessor(program: program)
            predicateEvaluator = try RepPredicateEvaluator(program: program)
            stateMachine = RepStateMachine(rep: rep)
            formEvaluator = try FormRuleEvaluator(program: program)
            formSummarizer = FormRuleScoreSummarizer(program: program)
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
            let formSnapshots = formEvaluator.update(
                timestampMS: frame.timestampMS,
                producedValues: produced,
                phase: repSnapshot.phase,
                frame: frame
            )
            return ProductPathEntry(
                rep: repSnapshot,
                formSnapshots: formSnapshots,
                formSummary: formSummarizer.summarize(formSnapshots)
            )
        }
    }

    private static func evaluator() throws -> FormRuleEvaluator {
        try FormRuleEvaluator(program: ProgramLoader.load(from: presetURL))
    }

    private static func summarizer() throws -> FormRuleScoreSummarizer {
        try FormRuleScoreSummarizer(program: ProgramLoader.load(from: presetURL))
    }

    private static func programWithEqualWeightRules() throws -> ExerciseProgram {
        let program = try ProgramLoader.load(from: presetURL)
        return ExerciseProgram(
            schemaVersion: program.schemaVersion,
            id: program.id,
            name: program.name,
            coordinateSpace: program.coordinateSpace,
            setup: program.setup,
            landmarkAliases: program.landmarkAliases,
            signals: program.signals,
            filters: program.filters,
            validity: program.validity,
            rep: program.rep,
            hold: program.hold,
            formRules: [
                FormRule(
                    id: "first",
                    when: "phase == 'bottom'",
                    expect: "knee <= 95",
                    minViolationMS: 0,
                    cue: "First cue",
                    severity: .warn,
                    scoreWeight: 5,
                    cooldownMS: 1500
                ),
                FormRule(
                    id: "second",
                    when: "phase == 'bottom'",
                    expect: "knee <= 95",
                    minViolationMS: 0,
                    cue: "Second cue",
                    severity: .warn,
                    scoreWeight: 5,
                    cooldownMS: 1500
                )
            ],
            set: program.set
        )
    }

    private static func snapshot(
        ruleID: String,
        isActive: Bool,
        expectationPassed: Bool?,
        cue: String? = nil,
        severity: RuleSeverity,
        violationDurationMS: Int? = nil,
        cueCooldownRemainingMS: Int? = nil,
        invalidReason: String? = nil
    ) -> FormRuleSnapshot {
        FormRuleSnapshot(
            ruleID: ruleID,
            isActive: isActive,
            expectationPassed: expectationPassed,
            cue: cue,
            severity: severity,
            violationDurationMS: violationDurationMS,
            cueCooldownRemainingMS: cueCooldownRemainingMS,
            invalidReason: invalidReason
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

    private static func format(_ snapshots: [FormRuleSnapshot]) -> String {
        snapshots.map(\.description).joined(separator: " | ")
    }
}
