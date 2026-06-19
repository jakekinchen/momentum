import Foundation

enum AppSettingsTab: Hashable {
    case account
    case feedback
    case camera
    case developer
}

final class AppSettingsSelection: ObservableObject {
    @Published var selectedTab: AppSettingsTab = .account
    @Published var accountPrompt: String?

    func promptForOpenAIChatSignIn() {
        selectedTab = .account
        accountPrompt = "Sign in to OpenAI to use chat."
    }

    func clearAccountPrompt() {
        accountPrompt = nil
    }
}
