import Foundation

public enum ArtifactLoader {
    public enum LoadError: Error { case missingResource }

    public static func bundledData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "kg_artifact.v0", withExtension: "json",
                                          subdirectory: "Artifact") else {
            throw LoadError.missingResource
        }
        return try Data(contentsOf: url)
    }

    /// Load the frozen artifact bundled into the KGKit module.
    public static func bundled() throws -> GraphArtifact {
        return try GraphArtifact.decode(from: bundledData())
    }
}
