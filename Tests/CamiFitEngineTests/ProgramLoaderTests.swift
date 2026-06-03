import XCTest
@testable import CamiFitEngine

final class ProgramLoaderTests: XCTestCase {
    func testBundledSquatPresetLoadsAndRoundTripsFromProductPath() throws {
        let program = try ProgramLoader.load(from: presetURL)

        XCTAssertEqual(program.schemaVersion, 1)
        XCTAssertEqual(program.id, "bodyweight_squat")
        XCTAssertEqual(program.name, "Bodyweight Squat")
        XCTAssertEqual(program.coordinateSpace, .image2D)
        XCTAssertEqual(program.rep?.phaseSignal, "knee")
        XCTAssertEqual(Set(program.signals.keys), ["knee_left", "knee_right", "knee_raw", "torso_raw", "knee_symmetry"])
        XCTAssertEqual(Set(program.filters.keys), ["knee", "torso_tilt"])
        XCTAssertEqual(program.setup.calibration["top_pose"]?.signals, ["knee", "torso_tilt"])
        XCTAssertEqual(program.formRules.map(\.id), ["depth", "torso", "symmetry"])
        XCTAssertEqual(program.set.targetReps, 10)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(program)
        let reloaded = try ProgramLoader.load(data: encoded)
        XCTAssertEqual(reloaded.id, program.id)
        XCTAssertEqual(reloaded.rep?.phaseSignal, program.rep?.phaseSignal)
        XCTAssertEqual(Set(reloaded.filters.keys), Set(program.filters.keys))
        XCTAssertEqual(reloaded.formRules.map(\.id), program.formRules.map(\.id))

        print("validated-summary \(program.validatedSummary)")
        print("validated-calibration top_pose signals=\(program.setup.calibration["top_pose"]?.signals ?? [])")
    }

    func testRejectsMissingRequiredPhaseSignalFixture() throws {
        let data = try Data(contentsOf: packageRoot.appendingPathComponent("Tests/CamiFitEngineTests/Fixtures/invalid_missing_phase_signal.json"))

        expectLoadError(from: data) { error in
            guard case let .missingRequiredField(field) = error else { return false }
            return field == "rep.phase_signal"
        }
    }

    func testRejectsRepPhaseSignalThatIsNotProduced() throws {
        let data = try mutatedPresetData { object in
            var rep = object["rep"] as! [String: Any]
            rep["phase_signal"] = "missing_phase"
            object["rep"] = rep
        }

        expectLoadError(from: data) { error in
            guard case let .missingReference(field, name) = error else { return false }
            return field == "rep.phase_signal" && name == "missing_phase"
        }
    }

    func testRejectsDanglingFilterSource() throws {
        let data = try mutatedPresetData { object in
            var filters = object["filters"] as! [String: Any]
            var knee = filters["knee"] as! [String: Any]
            knee["source"] = "missing_raw_signal"
            filters["knee"] = knee
            object["filters"] = filters
        }

        expectLoadError(from: data) { error in
            guard case let .missingReference(field, name) = error else { return false }
            return field == "filters.knee.source" && name == "missing_raw_signal"
        }
    }

    func testRejectsDanglingFormRuleReference() throws {
        let data = try mutatedPresetData { object in
            var rules = object["form_rules"] as! [[String: Any]]
            rules[0]["expect"] = "missing_depth <= 95"
            object["form_rules"] = rules
        }

        expectLoadError(from: data) { error in
            guard case let .missingReference(field, name) = error else { return false }
            return field == "form_rules[0].expect" && name == "missing_depth"
        }
    }

    func testRejectsInvalidEnumValue() throws {
        let data = try mutatedPresetData { object in
            var rules = object["form_rules"] as! [[String: Any]]
            rules[0]["severity"] = "urgent"
            object["form_rules"] = rules
        }

        expectLoadError(from: data) { error in
            guard case let .invalidEnumValue(field, value, allowed) = error else { return false }
            return field == "form_rules[0].severity" && value == "urgent" && allowed.contains("warn")
        }
    }

    func testRejectsUnknownCalibrationSignalReferenceFixture() throws {
        let data = try Data(contentsOf: packageRoot.appendingPathComponent("Tests/CamiFitEngineTests/Fixtures/invalid_calibration_signal_ref.json"))

        expectLoadError(from: data) { error in
            print("calibration-error \(error)")
            guard case let .invalidCalibrationSignalReference(field, name) = error else { return false }
            return field == "setup.calibration.top_pose.signals[0]" && name == "missing_calibration_signal"
        }
    }

    func testRejectsUnknownFunctionName() throws {
        let data = try mutatedPresetData { object in
            var signals = object["signals"] as! [String: Any]
            signals["knee_raw"] = "mystery_angle(primary.hip, primary.knee, primary.ankle)"
            object["signals"] = signals
        }

        expectLoadError(from: data) { error in
            guard case let .unknownFunction(field, name, _) = error else { return false }
            return field == "signals.knee_raw" && name == "mystery_angle"
        }
    }

    func testRejectsSignalDependencyCycle() throws {
        let data = try mutatedPresetData { object in
            var signals = object["signals"] as! [String: Any]
            signals["cycle_a"] = "cycle_b + 1"
            signals["cycle_b"] = "cycle_a + 1"
            object["signals"] = signals
        }

        expectLoadError(from: data) { error in
            guard case let .cyclicSignalReference(name) = error else { return false }
            return ["cycle_a", "cycle_b"].contains(name)
        }
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

    private func mutatedPresetData(_ mutate: (inout [String: Any]) -> Void) throws -> Data {
        let source = try Data(contentsOf: presetURL)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: source) as? [String: Any])
        mutate(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func expectLoadError(
        from data: Data,
        file: StaticString = #filePath,
        line: UInt = #line,
        matching matches: (ProgramLoadError) -> Bool
    ) {
        do {
            _ = try ProgramLoader.load(data: data)
            XCTFail("Expected ProgramLoadError", file: file, line: line)
        } catch let error as ProgramLoadError {
            XCTAssertTrue(matches(error), "Unexpected error: \(error)", file: file, line: line)
        } catch {
            XCTFail("Unexpected non-ProgramLoadError: \(error)", file: file, line: line)
        }
    }
}
