import SwiftUI

@main
struct CamiFitApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: AppExerciseSessionViewModel())
        }
    }
}
