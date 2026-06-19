import Foundation

enum FutureRoutineCatalog {
    static let foundationRoutine = WorkoutRoutine(
        id: "future-foundation-bodyweight",
        name: "Future Foundation Bodyweight",
        description: "A balanced starter routine using the built-in bodyweight movements.",
        blocks: [
            RoutineBlock(
                exerciseRef: .preset(id: "bodyweight_squat"),
                sets: 1,
                reps: 10,
                restSeconds: 45
            ),
            RoutineBlock(
                exerciseRef: .preset(id: "bodyweight_pushup"),
                sets: 1,
                reps: 8,
                restSeconds: 45
            ),
            RoutineBlock(
                exerciseRef: .preset(id: "bodyweight_lunge"),
                sets: 1,
                reps: 8,
                restSeconds: 0
            )
        ]
    )

    static let defaults = [foundationRoutine]
}
