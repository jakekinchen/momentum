import Foundation

public struct AppMockWorkerPreflightSuccess: Equatable {
    public let workerScriptURL: URL
    public let command: String
    public let runningMode: String
    public let message: String

    public init(workerScriptURL: URL, command: String, runningMode: String, message: String) {
        self.workerScriptURL = workerScriptURL
        self.command = command
        self.runningMode = runningMode
        self.message = message
    }
}

public struct AppMockWorkerPreflightFailure: Equatable {
    public let workerScriptURL: URL
    public let diagnosticText: String

    public init(workerScriptURL: URL, diagnosticText: String) {
        self.workerScriptURL = workerScriptURL
        self.diagnosticText = diagnosticText
    }
}

public enum AppMockWorkerPreflightStatus: Equatable {
    case idle
    case checking(URL)
    case succeeded(AppMockWorkerPreflightSuccess)
    case failed(AppMockWorkerPreflightFailure)

    public var displayText: String {
        switch self {
        case .idle:
            return "Mock worker not checked"
        case let .checking(url):
            return "Checking mock worker: \(url.path)"
        case let .succeeded(success):
            return "Mock worker ready: \(success.runningMode)"
        case let .failed(failure):
            return "Mock worker unavailable: \(failure.diagnosticText)"
        }
    }
}
