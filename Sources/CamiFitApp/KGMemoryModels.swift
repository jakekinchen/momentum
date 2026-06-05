import Foundation
import KGKit

struct KGMemoryItem: Identifiable, Equatable {
    let id: String
    let title: String
    let category: KGMemoryCategory
    let status: KGMemoryStatus
    let sourceText: String
    let createdAt: String
    let actor: GraphOperationActor
    let operationID: String
    let replacesOperationID: String?
    let reviewAfter: String?
    let evidence: [String]
    let reason: String?
}

enum KGMemoryCategory: Equatable {
    case healthSafety
    case preference
    case equipment
    case coachNote
    case sessionObservation
}

enum KGMemoryStatus: Equatable {
    case active
    case corrected
    case archived
}

struct KGMemoryViewState: Equatable {
    var phase: Phase
    var items: [KGMemoryItem]
    var overlayRevision: Int
    var baseArtifactShortHash: String
    var errorMessage: String?

    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case error
    }

    static let idle = KGMemoryViewState(
        phase: .idle,
        items: [],
        overlayRevision: 0,
        baseArtifactShortHash: "unknown",
        errorMessage: nil
    )
}
