import Combine
import Foundation

@MainActor
final class RoutineLibraryStore: ObservableObject {
    @Published private(set) var routines: [WorkoutRoutine] = []
    @Published private(set) var lastError: String?
    @Published var selectedRoutineID: String?

    private let store: RegimenStore
    private let defaultRoutines: [WorkoutRoutine]

    init(
        store: RegimenStore = RegimenStore(),
        defaultRoutines: [WorkoutRoutine] = FutureRoutineCatalog.defaults
    ) {
        self.store = store
        self.defaultRoutines = defaultRoutines
    }

    func load() {
        routines = Self.merge(defaultRoutines: defaultRoutines, savedRoutines: store.loadRoutines())
        if selectedRoutineID == nil || routines.contains(where: { $0.id == selectedRoutineID }) == false {
            selectedRoutineID = routines.first?.id
        }
        lastError = nil
    }

    func add(_ routine: WorkoutRoutine) throws {
        try store.saveRoutine(routine)
        load()
        if let saved = routines.first(where: { $0.hasSameContent(as: routine) }) {
            selectedRoutineID = saved.id
        }
    }

    func contains(_ routine: WorkoutRoutine) -> Bool {
        routines.contains { $0.hasSameContent(as: routine) }
    }

    func select(_ routine: WorkoutRoutine) {
        selectedRoutineID = routine.id
    }

    var selectedRoutine: WorkoutRoutine? {
        guard let selectedRoutineID else { return routines.first }
        return routines.first { $0.id == selectedRoutineID } ?? routines.first
    }

    private static func merge(
        defaultRoutines: [WorkoutRoutine],
        savedRoutines: [WorkoutRoutine]
    ) -> [WorkoutRoutine] {
        var merged = defaultRoutines
        for savedRoutine in savedRoutines {
            guard !merged.contains(where: { $0.id == savedRoutine.id || $0.hasSameContent(as: savedRoutine) }) else {
                continue
            }
            merged.append(savedRoutine)
        }
        return merged
    }
}
