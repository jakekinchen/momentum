import Combine
import Foundation
import KGKit

final class KGMemoryStore: ObservableObject {
    @Published private(set) var state: KGMemoryViewState = .idle

    private let applicationSupportDirectory: URL
    private let baseArtifactData: () throws -> Data
    private let fileManager: FileManager
    private var workspace: KGWorkspace?

    init(applicationSupportDirectory: URL? = nil,
         fileManager: FileManager = .default,
         baseArtifactData: @escaping () throws -> Data = { try ArtifactLoader.assessmentBundledData() }) {
        self.applicationSupportDirectory = applicationSupportDirectory ?? (try? KGWorkspace.applicationSupportDirectory()) ?? fileManager.temporaryDirectory
        self.fileManager = fileManager
        self.baseArtifactData = baseArtifactData
    }

    func load() {
        state.phase = .loading
        do {
            let prepared = try preparedWorkspace()
            try reload(from: prepared)
        } catch {
            state = KGMemoryViewState(
                phase: .error,
                items: [],
                overlayRevision: 0,
                baseArtifactShortHash: "unknown",
                errorMessage: String(describing: error)
            )
        }
    }

    @discardableResult
    func addHealthMemory(value: String,
                         sourceText: String,
                         reason: String,
                         actor: GraphOperationActor) throws -> KGMemoryItem {
        let workspace = try preparedWorkspace()
        let log = GraphOperationLog(url: workspace.memberOverlayURL, fileManager: fileManager)
        let operations = try log.readOperations()
        let operationID = "op-medical-\(Self.slug(value))-\(UUID().uuidString)"
        let operation = GraphOperation(
            operationID: operationID,
            operationType: .addMedicalConstraint,
            actor: actor,
            createdAt: Self.iso8601Now(),
            baseArtifactSHA256: workspace.baseArtifactSHA256,
            preconditionRevision: operations.count,
            scope: .member,
            sourceSpanIDs: ["ChatTurn:\(UUID().uuidString)"],
            effect: GraphOperationEffect(
                constraintType: "BodyRegion",
                value: value,
                sourceText: sourceText,
                hard: true,
                negated: false,
                reason: reason
            )
        )
        let validator = OverlayValidator(baseArtifactSHA256: workspace.baseArtifactSHA256)
        _ = try log.append(operation, validator: validator)
        try reload(from: workspace)
        guard let item = state.items.first(where: { $0.operationID == operationID }) else {
            throw StoreError.memoryNotFound(operationID)
        }
        return item
    }

    func correctHealthMemory(operationID: String, reason: String) throws {
        let workspace = try preparedWorkspace()
        let operations = try GraphOperationLog(url: workspace.memberOverlayURL, fileManager: fileManager).readOperations()
        guard operations.contains(where: { $0.operationID == operationID && $0.operationType == .addMedicalConstraint }) else {
            throw StoreError.memoryNotFound(operationID)
        }

        let revision = operations.count
        let operation = GraphOperation(
            operationID: "op-retract-\(operationID)-\(UUID().uuidString)",
            operationType: .retractMedicalConstraint,
            actor: .user,
            createdAt: Self.iso8601Now(),
            baseArtifactSHA256: workspace.baseArtifactSHA256,
            preconditionRevision: revision,
            scope: .member,
            effect: GraphOperationEffect(
                replacesOperationID: operationID,
                reason: reason
            )
        )
        let log = GraphOperationLog(url: workspace.memberOverlayURL, fileManager: fileManager)
        let validator = OverlayValidator(baseArtifactSHA256: workspace.baseArtifactSHA256)
        _ = try log.append(operation, validator: validator)
        try reload(from: workspace)
    }

    private func preparedWorkspace() throws -> KGWorkspace {
        if let workspace { return workspace }
        let prepared = try KGWorkspace.prepare(
            applicationSupportDirectory: applicationSupportDirectory,
            baseArtifactData: try baseArtifactData(),
            fileManager: fileManager
        )
        workspace = prepared
        return prepared
    }

    private func reload(from workspace: KGWorkspace) throws {
        let operations = try GraphOperationLog(url: workspace.memberOverlayURL, fileManager: fileManager).readOperations()
        let items = Self.projectMedicalMemories(from: operations)
        state = KGMemoryViewState(
            phase: items.isEmpty ? .empty : .loaded,
            items: items,
            overlayRevision: operations.count,
            baseArtifactShortHash: Self.shortHash(workspace.baseArtifactSHA256),
            errorMessage: nil
        )
    }

    static func projectMedicalMemories(from operations: [GraphOperation]) -> [KGMemoryItem] {
        let retractionsByTarget = Dictionary(
            operations.filter { $0.operationType == .retractMedicalConstraint }
                .compactMap { operation -> (String, GraphOperation)? in
                    guard let target = operation.effect.replacesOperationID else { return nil }
                    return (target, operation)
                },
            uniquingKeysWith: { first, _ in first }
        )

        return operations.compactMap { operation -> KGMemoryItem? in
            guard operation.operationType == .addMedicalConstraint else { return nil }
            let value = operation.effect.value ?? "health note"
            let retraction = retractionsByTarget[operation.operationID]
            return KGMemoryItem(
                id: operation.operationID,
                title: Self.title(forMedicalValue: value),
                category: .healthSafety,
                status: retraction == nil ? .active : .corrected,
                sourceText: operation.effect.sourceText ?? operation.effect.note ?? value,
                createdAt: operation.createdAt,
                actor: operation.actor,
                operationID: operation.operationID,
                replacesOperationID: retraction?.operationID,
                reviewAfter: operation.effect.reviewAfter,
                evidence: operation.sourceSpanIDs,
                reason: retraction?.effect.reason ?? operation.effect.reason ?? operation.effect.note
            )
        }
        .sorted { left, right in
            if left.status != right.status { return left.status == .active }
            return left.createdAt > right.createdAt
        }
    }

    private static func title(forMedicalValue value: String) -> String {
        value
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func shortHash(_ hash: String) -> String {
        String(hash.prefix(12))
    }

    private static func slug(_ value: String) -> String {
        value
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { partial, character in
                if character == "-", partial.last == "-" { return }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func iso8601Now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    enum StoreError: Error, Equatable {
        case workspaceNotLoaded
        case memoryNotFound(String)
    }
}
