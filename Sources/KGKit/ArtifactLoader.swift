import Foundation

public enum ArtifactLoader {
    public enum LoadError: Error { case missingResource }

    /// Load the frozen artifact bundled into the KGKit module.
    public static func bundled() throws -> GraphArtifact {
        guard let url = Bundle.module.url(forResource: "kg_artifact.v0", withExtension: "json",
                                          subdirectory: "Artifact") else {
            throw LoadError.missingResource
        }
        return try GraphArtifact.decode(from: Data(contentsOf: url))
    }
}
