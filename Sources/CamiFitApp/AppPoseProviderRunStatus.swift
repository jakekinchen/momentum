import Foundation

public struct AppPoseProviderRunDescriptor: Equatable {
    public let mode: String
    public let source: String

    public init(mode: String, source: String) {
        self.mode = mode
        self.source = source
    }
}

public struct AppPoseProviderRunStatusSummary: Equatable {
    public let descriptor: AppPoseProviderRunDescriptor
    public let frameCount: Int

    public init(descriptor: AppPoseProviderRunDescriptor, frameCount: Int) {
        self.descriptor = descriptor
        self.frameCount = frameCount
    }
}

public struct AppPoseProviderRunStatusFailure: Equatable {
    public let descriptor: AppPoseProviderRunDescriptor
    public let diagnosticText: String

    public init(descriptor: AppPoseProviderRunDescriptor, diagnosticText: String) {
        self.descriptor = descriptor
        self.diagnosticText = diagnosticText
    }
}

public enum AppPoseProviderRunStatus: Equatable {
    case idle
    case running(AppPoseProviderRunDescriptor)
    case succeeded(AppPoseProviderRunStatusSummary)
    case failed(AppPoseProviderRunStatusFailure)

    public var displayText: String {
        switch self {
        case .idle:
            return "Provider idle"
        case let .running(descriptor):
            return "Running \(descriptor.mode): \(descriptor.source)"
        case let .succeeded(summary):
            return "\(summary.descriptor.mode) succeeded: \(summary.frameCount) frame(s)"
        case let .failed(failure):
            return "\(failure.descriptor.mode) failed: \(failure.diagnosticText)"
        }
    }
}
