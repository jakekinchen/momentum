import Foundation

public enum ArtifactLoader {
    public enum LoadError: Error { case missingResource }

    private static func data(resource: String) throws -> Data {
        guard let url = KGKitResourceBundle.url(forResource: resource, withExtension: "json",
                                                subdirectory: "Artifact") else {
            throw LoadError.missingResource
        }
        return try Data(contentsOf: url)
    }

    public static func bundledData() throws -> Data {
        try data(resource: "kg_artifact.v0")
    }

    /// Load the frozen artifact bundled into the KGKit module.
    public static func bundled() throws -> GraphArtifact {
        return try GraphArtifact.decode(from: bundledData())
    }

    public static func assessmentBundledData() throws -> Data {
        try data(resource: "kg_artifact.assessment.v0")
    }

    /// Load the assignment-mode artifact generated from the frozen assessment snapshot.
    public static func assessmentBundled() throws -> GraphArtifact {
        try GraphArtifact.decode(from: assessmentBundledData())
    }

    public static func assessmentMemberGraphData() throws -> Data {
        try data(resource: "assessment_member_kg.generated")
    }
}
