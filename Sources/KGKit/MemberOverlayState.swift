import Foundation

public struct OverlayConstraint: Equatable, Sendable {
    public let operationID: String
    public let constraintType: String
    public let value: String
    public let sourceText: String
    public let hard: Bool
    public let negated: Bool
    public let reviewAfter: String?

    public var resolvedConstraint: ResolvedConstraint {
        ResolvedConstraint(
            constraintType: constraintType,
            value: value,
            hard: hard,
            sourceText: sourceText,
            negated: negated
        )
    }
}

public struct MemberOverlayState: Equatable, Sendable {
    public let revision: Int
    public let activeConstraints: [OverlayConstraint]
    public let retractedOperationIDs: Set<String>

    public init(operations: [GraphOperation]) {
        var constraintsByOperationID: [String: OverlayConstraint] = [:]
        var retracted: Set<String> = []

        for operation in operations {
            switch operation.operationType {
            case .addMedicalConstraint:
                guard let constraintType = operation.effect.constraintType,
                      let value = operation.effect.value else { continue }
                constraintsByOperationID[operation.operationID] = OverlayConstraint(
                    operationID: operation.operationID,
                    constraintType: constraintType,
                    value: value,
                    sourceText: operation.effect.sourceText ?? operation.effect.note ?? value,
                    hard: operation.effect.hard ?? true,
                    negated: operation.effect.negated ?? false,
                    reviewAfter: operation.effect.reviewAfter
                )
            case .retractMedicalConstraint:
                guard let target = operation.effect.replacesOperationID else { continue }
                retracted.insert(target)
                constraintsByOperationID.removeValue(forKey: target)
            case .addPreference, .retractPreference, .addEquipmentAccess,
                 .requestClarification, .archiveStaleObservation:
                continue
            }
        }

        self.revision = operations.count
        self.activeConstraints = constraintsByOperationID.values.sorted { $0.operationID < $1.operationID }
        self.retractedOperationIDs = retracted
    }

    public var resolvedConstraints: [ResolvedConstraint] {
        activeConstraints.map { $0.resolvedConstraint }
    }
}

public struct MergedGraphView: Sendable {
    public let baseArtifact: GraphArtifact
    public let graph: LocalGraph
    public let overlay: MemberOverlayState
    public let baseArtifactSHA256: String

    public init(workspace: KGWorkspace) throws {
        let artifact = try workspace.loadBaseArtifact()
        let log = GraphOperationLog(url: workspace.memberOverlayURL)
        self.baseArtifact = artifact
        self.graph = try LocalGraph(artifact: artifact)
        self.overlay = try MemberOverlayState(operations: log.readOperations())
        self.baseArtifactSHA256 = workspace.baseArtifactSHA256
    }

    public var activeResolvedConstraints: [ResolvedConstraint] {
        overlay.resolvedConstraints
    }
}

