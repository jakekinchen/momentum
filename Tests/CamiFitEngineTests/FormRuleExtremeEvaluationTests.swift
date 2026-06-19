import XCTest
@testable import CamiFitEngine

/// Episode-extreme form rules ("reach depth at the deepest point of the rep")
/// judge once per active episode instead of every frame, so a correct rep is
/// never penalized while ascending back through the bottom phase.
final class FormRuleExtremeEvaluationTests: XCTestCase {
    func testReachingDepthMidEpisodePassesTheWholeEpisode() throws {
        var evaluator = try Self.extremeDepthEvaluator()

        // Enter bottom shallow (pending), reach depth, rise back through the
        // shallow band, then leave the bottom phase.
        let entry = try Self.depth(evaluator.update(
            timestampMS: 0, producedValues: ["knee": .valid(99, confidence: 1)], phase: .bottom
        ))
        let deep = try Self.depth(evaluator.update(
            timestampMS: 300, producedValues: ["knee": .valid(92, confidence: 1)], phase: .bottom
        ))
        let rising = try Self.depth(evaluator.update(
            timestampMS: 600, producedValues: ["knee": .valid(120, confidence: 1)], phase: .bottom
        ))
        let verdict = try Self.depth(evaluator.update(
            timestampMS: 900, producedValues: ["knee": .valid(165, confidence: 1)], phase: .ascending
        ))

        XCTAssertTrue(entry.isActive)
        XCTAssertNil(entry.expectationPassed, "shallow entry is pending, not failing")
        XCTAssertNil(entry.cue)
        XCTAssertEqual(deep.expectationPassed, true)
        XCTAssertEqual(rising.expectationPassed, true, "latched depth must hold through the ascent")
        XCTAssertNil(rising.cue)
        XCTAssertTrue(verdict.isActive, "episode verdict is reported on the closing frame")
        XCTAssertEqual(verdict.expectationPassed, true)
        XCTAssertNil(verdict.cue)
    }

    func testEpisodeEndingWithoutDepthFailsOnceAndCues() throws {
        var evaluator = try Self.extremeDepthEvaluator()

        let entry = try Self.depth(evaluator.update(
            timestampMS: 0, producedValues: ["knee": .valid(99, confidence: 1)], phase: .bottom
        ))
        let shallowBottom = try Self.depth(evaluator.update(
            timestampMS: 400, producedValues: ["knee": .valid(98, confidence: 1)], phase: .bottom
        ))
        let verdict = try Self.depth(evaluator.update(
            timestampMS: 800, producedValues: ["knee": .valid(165, confidence: 1)], phase: .ascending
        ))
        let after = try Self.depth(evaluator.update(
            timestampMS: 900, producedValues: ["knee": .valid(170, confidence: 1)], phase: .ready
        ))

        XCTAssertNil(entry.expectationPassed)
        XCTAssertNil(shallowBottom.expectationPassed, "no mid-episode failure spam")
        XCTAssertNil(shallowBottom.cue)
        XCTAssertEqual(verdict.expectationPassed, false)
        XCTAssertEqual(verdict.cue, "Go deeper")
        XCTAssertEqual(verdict.violationDurationMS, 800)
        XCTAssertFalse(after.isActive, "verdict is emitted exactly once")
    }

    func testShortBounceEpisodeIsDiscarded() throws {
        var evaluator = try Self.extremeDepthEvaluator()

        _ = evaluator.update(
            timestampMS: 0, producedValues: ["knee": .valid(99, confidence: 1)], phase: .bottom
        )
        let verdict = try Self.depth(evaluator.update(
            timestampMS: 100, producedValues: ["knee": .valid(165, confidence: 1)], phase: .ready
        ))

        XCTAssertFalse(verdict.isActive, "an episode shorter than min_violation_ms is a bounce, not a judged rep")
        XCTAssertNil(verdict.cue)
    }

    func testCueCooldownSuppressesSecondFailedEpisode() throws {
        var evaluator = try Self.extremeDepthEvaluator()

        _ = evaluator.update(timestampMS: 0, producedValues: ["knee": .valid(99, confidence: 1)], phase: .bottom)
        let firstVerdict = try Self.depth(evaluator.update(
            timestampMS: 500, producedValues: ["knee": .valid(165, confidence: 1)], phase: .ready
        ))
        _ = evaluator.update(timestampMS: 700, producedValues: ["knee": .valid(99, confidence: 1)], phase: .bottom)
        let secondVerdict = try Self.depth(evaluator.update(
            timestampMS: 1_200, producedValues: ["knee": .valid(165, confidence: 1)], phase: .ready
        ))

        XCTAssertEqual(firstVerdict.cue, "Go deeper")
        XCTAssertEqual(secondVerdict.expectationPassed, false, "the failure still scores")
        XCTAssertNil(secondVerdict.cue, "but the cue respects the cooldown")
    }

    func testInvalidSignalFramesKeepEpisodePending() throws {
        var evaluator = try Self.extremeDepthEvaluator()

        _ = evaluator.update(timestampMS: 0, producedValues: ["knee": .valid(99, confidence: 1)], phase: .bottom)
        let invalid = try Self.depth(evaluator.update(
            timestampMS: 300, producedValues: ["knee": .invalid(reason: "occluded")], phase: .bottom
        ))
        _ = evaluator.update(timestampMS: 600, producedValues: ["knee": .valid(92, confidence: 1)], phase: .bottom)
        let verdict = try Self.depth(evaluator.update(
            timestampMS: 900, producedValues: ["knee": .valid(165, confidence: 1)], phase: .ready
        ))

        XCTAssertTrue(invalid.isActive)
        XCTAssertNil(invalid.expectationPassed)
        XCTAssertEqual(invalid.invalidReason, "signal knee invalid: occluded")
        XCTAssertEqual(verdict.expectationPassed, true, "depth reached after the dropout still passes the episode")
    }

    // MARK: - Helpers

    private static func depth(_ snapshots: [FormRuleSnapshot]) throws -> FormRuleSnapshot {
        try XCTUnwrap(snapshots.first { $0.ruleID == "depth" })
    }

    private static func extremeDepthEvaluator() throws -> FormRuleEvaluator {
        let program = try ProgramLoader.load(from: presetURL)
        let custom = ExerciseProgram(
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
                    id: "depth",
                    when: "phase == 'bottom'",
                    expect: "knee <= 95",
                    minViolationMS: 250,
                    cue: "Go deeper",
                    severity: .warn,
                    scoreWeight: 10,
                    cooldownMS: 1_500,
                    evaluation: .extreme
                )
            ],
            set: program.set
        )
        return try FormRuleEvaluator(program: custom)
    }

    private static var presetURL: URL {
        packageRoot.appendingPathComponent("Presets/bodyweight_squat.json")
    }

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
