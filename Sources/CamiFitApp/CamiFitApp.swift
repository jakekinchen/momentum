import AppKit
import Foundation
import SwiftUI

private enum MainWindowSizing {
    static let preferredSize = CGSize(width: 1300, height: 900)

    static func launchSize(for visibleRect: CGRect) -> CGSize {
        CGSize(
            width: min(preferredSize.width, visibleRect.width),
            height: min(preferredSize.height, visibleRect.height)
        )
    }
}

@main
struct CamiFitApp: App {
    @StateObject private var viewModel = AppExerciseSessionViewModel()
    @StateObject private var codex = CodexAppServerClient()
    @StateObject private var onboarding = OnboardingCoordinator()

    init() {
        CamiFitBrandLogo.applyAsApplicationIcon()
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup("Future Coach") {
            Group {
                if let synthetic = ProcessInfo.processInfo.environment["CAMIFIT_SYNTHETIC"], !synthetic.isEmpty {
                    SyntheticDemoView(viewModel: viewModel, framesURL: URL(fileURLWithPath: synthetic))
                } else {
                    ContentView(viewModel: viewModel, codex: codex)
                        .environmentObject(onboarding)
                }
            }
            .frame(minWidth: MainWindowSizing.preferredSize.width, minHeight: MainWindowSizing.preferredSize.height)
        }
        .windowStyle(.titleBar)
        .defaultSize(MainWindowSizing.preferredSize)
        .defaultWindowPlacement { _, context in
            WindowPlacement(size: MainWindowSizing.launchSize(for: context.defaultDisplay.visibleRect))
        }
        .commands {
            CommandMenu("Session") {
                Button("Reset Session") {
                    viewModel.resetLiveSession()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }

            CommandGroup(after: .help) {
                Button("Show Future Coach Tour") {
                    onboarding.showTour()
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }
        }

        Settings {
            CamiFitSettingsView()
                .environmentObject(codex)
        }
    }
}
