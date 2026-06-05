# Chat-Driven Regimen & Exercise Authoring — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the Codex coach generate workout routines and brand-new tracked exercises that the app parses, validates, renders as chat cards, and saves as runnable presets.

**Architecture:** The coach appends fenced ` ```camifit-exercise ` / ` ```camifit-routine ` JSON blocks to its replies. On turn completion, `RegimenBlockParser` extracts blocks, decodes them (`ProgramLoader.load(data:)`) and dry-runs each exercise through `FrameSignalProcessor` against a bundled sample frame. Valid results attach to the chat message and render as `RegimenCard`s; saving writes preset JSON to Application Support and the preset loader merges it into the Exercise picker.

**Tech Stack:** Swift, SwiftUI, CamiFitEngine, XCTest. Branch: `feat/chat-regimen` (off `feat/codex-coach-and-shell`).

**Spec:** `docs/superpowers/specs/2026-06-04-chat-regimen-authoring-design.md`

---

## File Structure

- Create `Sources/CamiFitApp/Regimen/WorkoutRoutine.swift` — `WorkoutRoutine`, `RoutineBlock`, `ExerciseRef` models (Codable).
- Create `Sources/CamiFitApp/Regimen/RegimenBlockParser.swift` — fenced-block extraction + exercise validation (decode + dry-run).
- Create `Sources/CamiFitApp/Regimen/RegimenStore.swift` — Application Support read/write for user presets + routines.
- Create `Sources/CamiFitApp/Regimen/RegimenCard.swift` — SwiftUI exercise/routine/error cards.
- Modify `Sources/CamiFitApp/AppExerciseSessionViewModel.swift` — merge preset sources, add Application Support candidate, `saveGeneratedExercise`.
- Modify `Sources/CamiFitApp/CodexAppServerClient.swift` — extend instructions with the authoring contract + template.
- Modify `Sources/CamiFitApp/ContentView.swift` — parse on `finish`, attach payload to `ChatMessage`, render cards.
- Tests under `Tests/CamiFitAppTests/`.

---

## Task 1: Routine data model

**Files:**
- Create: `Sources/CamiFitApp/Regimen/WorkoutRoutine.swift`
- Test: `Tests/CamiFitAppTests/WorkoutRoutineTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CamiFitApp
import CamiFitEngine

final class WorkoutRoutineTests: XCTestCase {
    func testDecodesRoutineWithPresetRef() throws {
        let json = """
        {"id":"r1","name":"Leg Day","description":"x",
         "blocks":[{"exerciseRef":{"preset":"bodyweight_squat"},"sets":3,"reps":10,"restSeconds":60}]}
        """.data(using: .utf8)!
        let routine = try JSONDecoder().decode(WorkoutRoutine.self, from: json)
        XCTAssertEqual(routine.blocks.count, 1)
        XCTAssertEqual(routine.blocks[0].sets, 3)
        if case let .preset(id) = routine.blocks[0].exerciseRef { XCTAssertEqual(id, "bodyweight_squat") }
        else { XCTFail("expected preset ref") }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter WorkoutRoutineTests`
Expected: FAIL — `cannot find 'WorkoutRoutine' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import CamiFitEngine
import Foundation

/// How a routine block references its exercise: an existing preset id, or a brand-new
/// inline ExerciseProgram authored by the coach.
enum ExerciseRef: Codable, Equatable {
    case preset(id: String)
    case inline(ExerciseProgram)

    private enum CodingKeys: String, CodingKey { case preset, inline }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try c.decodeIfPresent(String.self, forKey: .preset) {
            self = .preset(id: id)
        } else {
            self = .inline(try c.decode(ExerciseProgram.self, forKey: .inline))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .preset(id): try c.encode(id, forKey: .preset)
        case let .inline(program): try c.encode(program, forKey: .inline)
        }
    }
}

struct RoutineBlock: Codable, Equatable {
    var exerciseRef: ExerciseRef
    var sets: Int
    var reps: Int?
    var holdSeconds: Double?
    var restSeconds: Int
}

struct WorkoutRoutine: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var description: String
    var blocks: [RoutineBlock]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter WorkoutRoutineTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CamiFitApp/Regimen/WorkoutRoutine.swift Tests/CamiFitAppTests/WorkoutRoutineTests.swift
git commit -m "feat: WorkoutRoutine/RoutineBlock/ExerciseRef models"
```

---

## Task 2: Extract fenced blocks from assistant text

**Files:**
- Create: `Sources/CamiFitApp/Regimen/RegimenBlockParser.swift`
- Test: `Tests/CamiFitAppTests/RegimenBlockParserExtractTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CamiFitApp

final class RegimenBlockParserExtractTests: XCTestCase {
    func testExtractsBothBlockKindsFromMixedProse() {
        let text = """
        Here is a plan!
        ```camifit-routine
        {"id":"r1"}
        ```
        And a new move:
        ```camifit-exercise
        {"id":"e1"}
        ```
        Enjoy.
        """
        let blocks = RegimenBlockParser.extractBlocks(from: text)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].kind, .routine)
        XCTAssertEqual(blocks[0].json, "{\"id\":\"r1\"}")
        XCTAssertEqual(blocks[1].kind, .exercise)
    }

    func testNoBlocksReturnsEmpty() {
        XCTAssertTrue(RegimenBlockParser.extractBlocks(from: "just text").isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RegimenBlockParserExtractTests`
Expected: FAIL — `cannot find 'RegimenBlockParser' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import CamiFitEngine
import Foundation

enum RegimenBlockKind: String, Equatable {
    case exercise = "camifit-exercise"
    case routine = "camifit-routine"
}

struct RegimenRawBlock: Equatable {
    let kind: RegimenBlockKind
    let json: String
}

enum RegimenBlockParser {
    /// Finds ```camifit-exercise / ```camifit-routine fenced blocks in arbitrary prose.
    static func extractBlocks(from text: String) -> [RegimenRawBlock] {
        var blocks: [RegimenRawBlock] = []
        let lines = text.components(separatedBy: "\n")
        var current: RegimenBlockKind?
        var buffer: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if current == nil {
                if trimmed == "```camifit-exercise" { current = .exercise; buffer = [] }
                else if trimmed == "```camifit-routine" { current = .routine; buffer = [] }
            } else if trimmed == "```" {
                if let kind = current {
                    blocks.append(RegimenRawBlock(kind: kind, json: buffer.joined(separator: "\n")))
                }
                current = nil
                buffer = []
            } else {
                buffer.append(line)
            }
        }
        return blocks
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RegimenBlockParserExtractTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CamiFitApp/Regimen/RegimenBlockParser.swift Tests/CamiFitAppTests/RegimenBlockParserExtractTests.swift
git commit -m "feat: extract camifit fenced blocks from chat text"
```

---

## Task 3: Validate an exercise block (decode + dry-run)

**Files:**
- Modify: `Sources/CamiFitApp/Regimen/RegimenBlockParser.swift`
- Test: `Tests/CamiFitAppTests/RegimenBlockParserValidateTests.swift`

**Context:** A neutral sample frame comes from the bundled `synthetic_squat_demo.jsonl` (decoded via `MediaPipePoseJSONLDecoder`, frame 0) — it carries the full real landmark namespace, so constructing+running `FrameSignalProcessor` surfaces bad signal expressions and unknown landmarks.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CamiFitApp
import CamiFitEngine

final class RegimenBlockParserValidateTests: XCTestCase {
    private func squatJSON() throws -> String {
        let url = Bundle.module.url(forResource: "bodyweight_squat", withExtension: "json", subdirectory: "Presets")!
        return String(data: try Data(contentsOf: url), encoding: .utf8)!
    }

    func testValidExerciseDecodesAndDryRuns() throws {
        let result = RegimenBlockParser.validateExercise(json: try squatJSON())
        guard case let .success(program) = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(program.id, "bodyweight_squat")
    }

    func testMalformedJSONFails() {
        let result = RegimenBlockParser.validateExercise(json: "{ not json")
        guard case .failure = result else { return XCTFail("expected failure") }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RegimenBlockParserValidateTests`
Expected: FAIL — `type 'RegimenBlockParser' has no member 'validateExercise'`.

- [ ] **Step 3: Write minimal implementation** (append to `RegimenBlockParser.swift`)

```swift
enum RegimenValidationError: Error, Equatable {
    case decode(String)
    case evaluation(String)
    case noSampleFrame
}

extension RegimenBlockParser {
    static func validateExercise(json: String) -> Result<ExerciseProgram, RegimenValidationError> {
        guard let data = json.data(using: .utf8) else { return .failure(.decode("not utf8")) }
        let program: ExerciseProgram
        do { program = try ProgramLoader.load(data: data) }
        catch { return .failure(.decode(String(describing: error))) }

        guard let frame = sampleFrame() else { return .failure(.noSampleFrame) }
        do {
            var processor = try FrameSignalProcessor(program: program)
            _ = processor.process(frame: frame)
        } catch {
            return .failure(.evaluation(String(describing: error)))
        }
        return .success(program)
    }

    /// First frame of the bundled synthetic squat trace — a real full-landmark frame.
    static func sampleFrame() -> PoseFrame? {
        guard let url = Bundle.module.url(forResource: "synthetic_squat_demo", withExtension: "jsonl", subdirectory: "Demo"),
              let frames = try? MediaPipePoseJSONLDecoder.decode(contentsOf: url) else { return nil }
        return frames.first
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RegimenBlockParserValidateTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CamiFitApp/Regimen/RegimenBlockParser.swift Tests/CamiFitAppTests/RegimenBlockParserValidateTests.swift
git commit -m "feat: validate generated exercises via decode + dry-run"
```

---

## Task 4: Merge preset sources (bundled + user dir)

**Files:**
- Modify: `Sources/CamiFitApp/AppExerciseSessionViewModel.swift:366-374` (`defaultPresetSourceCandidates`) and `:414-423` (`resolvePresetSummaries`)
- Test: `Tests/CamiFitAppTests/PresetMergeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CamiFitApp

final class PresetMergeTests: XCTestCase {
    func testMergesTwoDirsUserWinsOnIdCollision() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("camifit-\(UUID().uuidString)")
        let bundled = base.appendingPathComponent("bundled"); let user = base.appendingPathComponent("user")
        try fm.createDirectory(at: bundled, withIntermediateDirectories: true)
        try fm.createDirectory(at: user, withIntermediateDirectories: true)
        let squat = Bundle.module.url(forResource: "bodyweight_squat", withExtension: "json", subdirectory: "Presets")!
        try fm.copyItem(at: squat, to: bundled.appendingPathComponent("bodyweight_squat.json"))
        try fm.copyItem(at: squat, to: user.appendingPathComponent("bodyweight_squat.json")) // collision
        let merged = AppExerciseSessionViewModel.mergedPresetSummaries(from: [bundled, user])
        XCTAssertEqual(merged.filter { $0.id == "bodyweight_squat" }.count, 1, "user wins, no dupes")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PresetMergeTests`
Expected: FAIL — no member `mergedPresetSummaries`.

- [ ] **Step 3: Write minimal implementation**

Replace `resolvePresetSummaries` body and add `mergedPresetSummaries` + user dir. In `defaultPresetSourceCandidates()`, append:

```swift
        candidates.append(RegimenStore.userPresetsDirectory())
```

Replace `resolvePresetSummaries`:

```swift
    private static func resolvePresetSummaries(from candidates: [URL]) -> (sourceURL: URL?, presets: [AppPresetSummary]) {
        let merged = mergedPresetSummaries(from: candidates)
        let source = candidates.first { !loadPresetSummaries(from: $0).isEmpty }
        return (source, merged)
    }

    /// Merge every candidate directory; later candidates win on id collision.
    static func mergedPresetSummaries(from candidates: [URL]) -> [AppPresetSummary] {
        var byID: [String: AppPresetSummary] = [:]
        for candidate in candidates {
            for preset in loadPresetSummaries(from: candidate) { byID[preset.id] = preset }
        }
        return byID.values.sorted { $0.name < $1.name }
    }
```

(Note: `RegimenStore.userPresetsDirectory()` is created in Task 5; this task's test only calls `mergedPresetSummaries`, so it compiles once Task 5 lands. If implementing strictly in order, temporarily inline the dir append after Task 5. Recommended: do Task 5 before re-running the full suite.)

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PresetMergeTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CamiFitApp/AppExerciseSessionViewModel.swift Tests/CamiFitAppTests/PresetMergeTests.swift
git commit -m "feat: merge bundled + user preset directories"
```

---

## Task 5: RegimenStore — persist user presets + routines

**Files:**
- Create: `Sources/CamiFitApp/Regimen/RegimenStore.swift`
- Test: `Tests/CamiFitAppTests/RegimenStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CamiFitApp
import CamiFitEngine

final class RegimenStoreTests: XCTestCase {
    func testSaveExerciseWritesJSONToUserPresets() throws {
        let store = RegimenStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let squat = try ProgramLoader.load(from: Bundle.module.url(forResource: "bodyweight_squat", withExtension: "json", subdirectory: "Presets")!)
        let url = try store.saveExercise(squat)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let reloaded = try ProgramLoader.load(from: url)
        XCTAssertEqual(reloaded.id, squat.id)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RegimenStoreTests`
Expected: FAIL — `cannot find 'RegimenStore' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import CamiFitEngine
import Foundation

struct RegimenStore {
    let root: URL

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CamiFit", isDirectory: true)
    }

    static func userPresetsDirectory() -> URL { RegimenStore().presetsDir }

    var presetsDir: URL { root.appendingPathComponent("Presets", isDirectory: true) }
    var routinesDir: URL { root.appendingPathComponent("Routines", isDirectory: true) }

    @discardableResult
    func saveExercise(_ program: ExerciseProgram) throws -> URL {
        try FileManager.default.createDirectory(at: presetsDir, withIntermediateDirectories: true)
        let url = presetsDir.appendingPathComponent("\(program.id).json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(program).write(to: url)
        return url
    }

    @discardableResult
    func saveRoutine(_ routine: WorkoutRoutine) throws -> URL {
        try FileManager.default.createDirectory(at: routinesDir, withIntermediateDirectories: true)
        let url = routinesDir.appendingPathComponent("\(routine.id).json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(routine).write(to: url)
        return url
    }

    func loadRoutines() -> [WorkoutRoutine] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: routinesDir, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(WorkoutRoutine.self, from: Data(contentsOf: $0)) }
            .sorted { $0.name < $1.name }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RegimenStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CamiFitApp/Regimen/RegimenStore.swift Tests/CamiFitAppTests/RegimenStoreTests.swift
git commit -m "feat: RegimenStore persists user presets + routines"
```

---

## Task 6: View-model save hook

**Files:**
- Modify: `Sources/CamiFitApp/AppExerciseSessionViewModel.swift` (add method near `loadAvailablePresets`, ~line 87)
- Test: `Tests/CamiFitAppTests/SaveGeneratedExerciseTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CamiFitApp
import CamiFitEngine

final class SaveGeneratedExerciseTests: XCTestCase {
    func testSavedExerciseBecomesSelectable() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = RegimenStore(root: tmp)
        let vm = AppExerciseSessionViewModel(presetSourceCandidates: [store.presetsDir])
        let squat = try ProgramLoader.load(from: Bundle.module.url(forResource: "bodyweight_squat", withExtension: "json", subdirectory: "Presets")!)
        try vm.saveGeneratedExercise(squat, store: store)
        XCTAssertTrue(vm.availablePresets.contains { $0.id == "bodyweight_squat" })
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SaveGeneratedExerciseTests`
Expected: FAIL — no member `saveGeneratedExercise`.

- [ ] **Step 3: Write minimal implementation**

```swift
    public func saveGeneratedExercise(_ program: ExerciseProgram, store: RegimenStore = RegimenStore()) throws {
        try store.saveExercise(program)
        loadAvailablePresets()
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SaveGeneratedExerciseTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CamiFitApp/AppExerciseSessionViewModel.swift Tests/CamiFitAppTests/SaveGeneratedExerciseTests.swift
git commit -m "feat: save generated exercise and refresh picker"
```

---

## Task 7: Parsed-regimen payload on chat messages

**Files:**
- Modify: `Sources/CamiFitApp/ContentView.swift` (`ChatMessage`, `ChatViewModel.finish`)
- Test: `Tests/CamiFitAppTests/ChatRegimenParseTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import CamiFitApp

final class ChatRegimenParseTests: XCTestCase {
    func testParseAttachesExerciseCardToMessage() throws {
        let squat = try String(contentsOf: Bundle.module.url(forResource: "bodyweight_squat", withExtension: "json", subdirectory: "Presets")!)
        let text = "Try this:\n```camifit-exercise\n\(squat)\n```"
        let results = RegimenBlockParser.parse(message: text)
        XCTAssertEqual(results.count, 1)
        if case .exercise = results[0] {} else { XCTFail("expected exercise result") }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ChatRegimenParseTests`
Expected: FAIL — no member `parse(message:)`.

- [ ] **Step 3: Write minimal implementation** (append to `RegimenBlockParser.swift`)

```swift
enum RegimenResult: Equatable {
    case exercise(ExerciseProgram)
    case routine(WorkoutRoutine)
    case invalid(kind: RegimenBlockKind, message: String)
}

extension RegimenBlockParser {
    static func parse(message: String) -> [RegimenResult] {
        extractBlocks(from: message).map { block in
            switch block.kind {
            case .exercise:
                switch validateExercise(json: block.json) {
                case let .success(program): return .exercise(program)
                case let .failure(error): return .invalid(kind: .exercise, message: String(describing: error))
                }
            case .routine:
                guard let data = block.json.data(using: .utf8),
                      let routine = try? JSONDecoder().decode(WorkoutRoutine.self, from: data) else {
                    return .invalid(kind: .routine, message: "Could not parse routine JSON.")
                }
                return .routine(routine)
            }
        }
    }
}
```

Then in `ContentView.swift`, add `var regimen: [RegimenResult] = []` to `ChatMessage`, and in `ChatViewModel.finish(_:)` after setting text, populate it:

```swift
    private func finish(_ id: UUID) {
        isResponding = false
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        if messages[idx].text.isEmpty { messages[idx].text = "(No response.)" }
        messages[idx].regimen = RegimenBlockParser.parse(message: messages[idx].text)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ChatRegimenParseTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/CamiFitApp/Regimen/RegimenBlockParser.swift Sources/CamiFitApp/ContentView.swift Tests/CamiFitAppTests/ChatRegimenParseTests.swift
git commit -m "feat: attach parsed regimen results to chat messages"
```

---

## Task 8: Agent authoring contract

**Files:**
- Modify: `Sources/CamiFitApp/CodexAppServerClient.swift` (`baseInstructions`)

- [ ] **Step 1: Extend `baseInstructions`** to append the authoring contract (no test — verified live in Task 11). Replace the `baseInstructions` string with one that also says:

```
When the user asks you to create a workout or a new exercise, reply with a short
encouraging explanation AND a single fenced code block the app can read:
- For a routine: ```camifit-routine with JSON {id,name,description,blocks:[{exerciseRef:{preset:"<id>"} OR {inline:<ExerciseProgram>}, sets, reps, holdSeconds, restSeconds}]}.
- For a brand-new exercise: ```camifit-exercise with a full ExerciseProgram JSON.
Use this exact existing exercise as your template and keep schemaVersion 1; signals are
angle(...) expressions over landmarks like primary.hip/primary.knee/primary.ankle; provide
a "rep" block OR a "hold" block. Template:
<paste the full contents of Resources/Presets/bodyweight_squat.json here>
```

- [ ] **Step 2: Build**

Run: `swift build --product CamiFitApp`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add Sources/CamiFitApp/CodexAppServerClient.swift
git commit -m "feat: teach the coach to author exercises/routines as fenced blocks"
```

---

## Task 9: Regimen cards UI

**Files:**
- Create: `Sources/CamiFitApp/Regimen/RegimenCard.swift`

- [ ] **Step 1: Implement the cards** (no unit test — SwiftUI views; verified visually in Task 11)

```swift
import CamiFitEngine
import SwiftUI

struct RegimenCard: View {
    let result: RegimenResult
    @EnvironmentObject private var model: AppExerciseSessionViewModel
    @State private var saved = false

    var body: some View {
        switch result {
        case let .exercise(program): exerciseCard(program)
        case let .routine(routine): routineCard(routine)
        case let .invalid(kind, message): invalidCard(kind, message)
        }
    }

    private func exerciseCard(_ program: ExerciseProgram) -> some View {
        card(title: program.name, subtitle: program.hold == nil ? "Counts reps" : "Timed hold", icon: "figure.strengthtraining.functional") {
            Text("Generated — may need tuning").font(.caption2).foregroundStyle(.orange)
            HStack {
                Button(saved ? "Added" : "Save & add to exercises") {
                    try? model.saveGeneratedExercise(program); saved = true
                }.buttonStyle(.borderedProminent).disabled(saved)
            }
        }
    }

    private func routineCard(_ routine: WorkoutRoutine) -> some View {
        card(title: routine.name, subtitle: routine.description, icon: "list.bullet.rectangle") {
            ForEach(Array(routine.blocks.enumerated()), id: \.offset) { _, block in
                Text("• \(refLabel(block.exerciseRef)) — \(block.sets)×\(block.reps.map(String.init) ?? block.holdSeconds.map { "\(Int($0))s" } ?? "?")")
                    .font(.caption)
            }
            Button("Start routine") { try? model.startRoutine(routine) }.buttonStyle(.bordered)
        }
    }

    private func invalidCard(_ kind: RegimenBlockKind, _ message: String) -> some View {
        card(title: "Couldn't read that \(kind == .exercise ? "exercise" : "routine")", subtitle: "Ask the coach to revise.", icon: "exclamationmark.triangle") {
            Text(message).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
        }
    }

    private func refLabel(_ ref: ExerciseRef) -> String {
        switch ref { case let .preset(id): return id; case let .inline(p): return p.name }
    }

    @ViewBuilder
    private func card<C: View>(title: String, subtitle: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .frame(maxWidth: 280, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 14, style: .continuous))
    }
}
```

- [ ] **Step 2: Add `startRoutine` stub to the view model** (full behavior in Task 11):

In `AppExerciseSessionViewModel.swift`:

```swift
    @Published public private(set) var activeRoutine: WorkoutRoutine?
    @Published public private(set) var activeRoutineBlockIndex: Int = 0

    public func startRoutine(_ routine: WorkoutRoutine) throws {
        activeRoutine = routine
        activeRoutineBlockIndex = 0
        if case let .preset(id) = routine.blocks.first?.exerciseRef { try? selectPreset(id: id) }
    }
```

- [ ] **Step 3: Build**

Run: `swift build --product CamiFitApp`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add Sources/CamiFitApp/Regimen/RegimenCard.swift Sources/CamiFitApp/AppExerciseSessionViewModel.swift
git commit -m "feat: regimen/exercise/error cards + routine start"
```

---

## Task 10: Render cards in the chat transcript

**Files:**
- Modify: `Sources/CamiFitApp/ContentView.swift` (`ChatBubble` / transcript `ForEach`)

- [ ] **Step 1: Render the card under assistant bubbles.** In the transcript `ForEach(chat.messages)`, wrap each message:

```swift
VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
    ChatBubble(message: message)
    ForEach(Array(message.regimen.enumerated()), id: \.offset) { _, result in
        RegimenCard(result: result)
    }
}
.id(message.id)
```

- [ ] **Step 2: Build**

Run: `swift build --product CamiFitApp`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add Sources/CamiFitApp/ContentView.swift
git commit -m "feat: render regimen cards inline in the coach chat"
```

---

## Task 11: Routine progress strip + live verification

**Files:**
- Modify: `Sources/CamiFitApp/ContentView.swift` (hero overlay)

- [ ] **Step 1: Show a routine progress strip in the hero** when `model.activeRoutine != nil`:

```swift
if let routine = model.activeRoutine {
    HStack(spacing: 8) {
        Text(routine.name).font(.caption.weight(.semibold))
        Text("Block \(model.activeRoutineBlockIndex + 1) of \(routine.blocks.count)").font(.caption2).foregroundStyle(.secondary)
        Button("Next") { model.advanceRoutine() }.buttonStyle(.bordered).controlSize(.mini)
    }
    .padding(8)
    .glassEffect(.regular, in: .capsule)
}
```

- [ ] **Step 2: Add `advanceRoutine` to the view model:**

```swift
    public func advanceRoutine() {
        guard let routine = activeRoutine else { return }
        let next = activeRoutineBlockIndex + 1
        guard next < routine.blocks.count else { activeRoutine = nil; return }
        activeRoutineBlockIndex = next
        if case let .preset(id) = routine.blocks[next].exerciseRef { try? selectPreset(id: id) }
    }
```

- [ ] **Step 3: Build + headless suite**

Run: `swift build --product CamiFitApp && swift test`
Expected: build exit 0; all tests pass (existing 114 + new).

- [ ] **Step 4: Live verification (manual)**

Run: `bash scripts/build_camifit_app.sh`, open the chat, send: "Create a standing calf raise exercise I can track." Confirm the reply renders an exercise card; tap **Save & add to exercises**; open the Exercise picker and confirm it appears; ask for "a 3-round leg routine" and confirm a routine card with Start.

- [ ] **Step 5: Commit**

```bash
git add Sources/CamiFitApp/ContentView.swift Sources/CamiFitApp/AppExerciseSessionViewModel.swift
git commit -m "feat: routine progress strip + advance"
```

---

## Self-Review Notes

- **Spec coverage:** data model (T1), agent contract (T8), parse+validate (T2/T3/T7), persistence+merge (T4/T5/T6), cards (T9/T10), routine run (T9/T11), caveat label (T9). ✓
- **Type consistency:** `RegimenBlockParser.extractBlocks` / `validateExercise` / `parse`; `RegimenResult` cases `.exercise/.routine/.invalid`; `RegimenStore.presetsDir/userPresetsDirectory/saveExercise/saveRoutine`; `AppExerciseSessionViewModel.mergedPresetSummaries/saveGeneratedExercise/startRoutine/advanceRoutine/activeRoutine`. Used consistently across tasks. ✓
- **Ordering note:** Task 4 references `RegimenStore.userPresetsDirectory()` (Task 5). Implement Task 5 before re-running the full suite, or land Tasks 1-3 then 5 then 4. Called out in Task 4.
- **Non-goals honored:** no avatar, no edit-form, local-only. ✓
