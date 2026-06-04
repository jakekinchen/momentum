import AppKit
import Foundation
import SwiftUI

@main
struct CamiFitApp: App {
    @StateObject private var viewModel = AppExerciseSessionViewModel()
    @StateObject private var codex = CodexAppServerClient()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup("CamiFit") {
            Group {
                if let synthetic = ProcessInfo.processInfo.environment["CAMIFIT_SYNTHETIC"], !synthetic.isEmpty {
                    SyntheticDemoView(viewModel: viewModel, framesURL: URL(fileURLWithPath: synthetic))
                } else {
                    ContentView(viewModel: viewModel, codex: codex)
                }
            }
            .frame(minWidth: 1100, minHeight: 720)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandMenu("Session") {
                Button("Reset Session") {
                    viewModel.resetLiveSession()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            CamiFitSettingsView()
                .environmentObject(codex)
        }
    }
}
