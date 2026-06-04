import Foundation
import SwiftUI

@main
struct CamiFitApp: App {
    @StateObject private var viewModel = AppExerciseSessionViewModel()

    var body: some Scene {
        WindowGroup {
            if let synthetic = ProcessInfo.processInfo.environment["CAMIFIT_SYNTHETIC"], !synthetic.isEmpty {
                SyntheticDemoView(viewModel: viewModel, framesURL: URL(fileURLWithPath: synthetic))
            } else {
                ContentView(viewModel: viewModel)
            }
        }
    }
}
