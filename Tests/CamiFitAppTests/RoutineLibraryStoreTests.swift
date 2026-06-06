import XCTest
@testable import CamiFitApp

final class RoutineLibraryStoreTests: XCTestCase {
    @MainActor
    func testAddRoutinePersistsAndRefreshesLibrary() throws {
        let regimenStore = RegimenStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let library = RoutineLibraryStore(store: regimenStore, defaultRoutines: [])
        let routine = WorkoutRoutine(
            id: "core-builder",
            name: "Core Builder",
            description: "Bodyweight core",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_plank"), sets: 3, reps: nil, holdSeconds: 30, restSeconds: 45)
            ]
        )

        library.load()
        XCTAssertEqual(library.routines, [])
        XCTAssertFalse(library.contains(routine))

        try library.add(routine)

        XCTAssertEqual(library.routines, [routine])
        XCTAssertTrue(library.contains(routine))
        XCTAssertEqual(regimenStore.loadRoutines(), [routine])

        print("routine-library add=true routines=\(library.routines.count)")
    }

    @MainActor
    func testContainsMatchesSavedRoutineAfterCollisionRename() throws {
        let regimenStore = RegimenStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let library = RoutineLibraryStore(store: regimenStore, defaultRoutines: [])
        let existing = WorkoutRoutine(
            id: "core-builder",
            name: "Core Builder",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_plank"), sets: 2, holdSeconds: 20)
            ]
        )
        let generated = WorkoutRoutine(
            id: "core-builder",
            name: "Core Builder",
            description: "A longer hold progression",
            blocks: [
                RoutineBlock(exerciseRef: .preset(id: "bodyweight_plank"), sets: 3, holdSeconds: 30)
            ]
        )

        try regimenStore.saveRoutine(existing)
        try library.add(generated)

        XCTAssertTrue(library.contains(generated))
        XCTAssertEqual(Set(library.routines.map(\.id)), ["core-builder", "core-builder-2"])
    }

    @MainActor
    func testDefaultLibraryIncludesGoldenFutureRoutine() {
        let regimenStore = RegimenStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let library = RoutineLibraryStore(store: regimenStore)

        library.load()

        XCTAssertEqual(library.routines.first?.id, FutureRoutineCatalog.foundationRoutine.id)
        XCTAssertEqual(library.routines.first?.blocks.count, 4)
    }
}
