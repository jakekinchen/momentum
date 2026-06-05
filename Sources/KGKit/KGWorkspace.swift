import CryptoKit
import Foundation

public struct KGWorkspace: Sendable {
    public let rootURL: URL
    public let baseDirectoryURL: URL
    public let memberOverlayURL: URL
    public let opsDirectoryURL: URL
    public let snapshotsDirectoryURL: URL
    public let receiptsDirectoryURL: URL
    public let baseArtifactURL: URL
    public let baseArtifactSHA256: String

    public enum WorkspaceError: Error, Equatable {
        case existingBaseArtifactHashMismatch(expected: String, actual: String)
    }

    public static func applicationSupportDirectory(appName: String = "CamiFit",
                                                   fileManager: FileManager = .default) throws -> URL {
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = urls[0].appendingPathComponent(appName, isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Prepare Application Support/CamiFit/KnowledgeGraph from a frozen artifact.
    /// The base artifact is content-addressed and never overwritten in place.
    public static func prepare(applicationSupportDirectory: URL,
                               baseArtifactData: Data,
                               fileManager: FileManager = .default) throws -> KGWorkspace {
        let root = applicationSupportDirectory.appendingPathComponent("KnowledgeGraph", isDirectory: true)
        let baseDirectory = root.appendingPathComponent("base", isDirectory: true)
        let overlaysDirectory = root.appendingPathComponent("overlays/member", isDirectory: true)
        let opsDirectory = root.appendingPathComponent("ops", isDirectory: true)
        let snapshotsDirectory = root.appendingPathComponent("snapshots", isDirectory: true)
        let receiptsDirectory = root.appendingPathComponent("receipts", isDirectory: true)

        for directory in [baseDirectory, overlaysDirectory, opsDirectory, snapshotsDirectory, receiptsDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let sha = sha256Hex(baseArtifactData)
        let baseURL = baseDirectory.appendingPathComponent("\(sha).kgart.json")
        if fileManager.fileExists(atPath: baseURL.path) {
            let actual = try sha256Hex(Data(contentsOf: baseURL))
            guard actual == sha else {
                throw WorkspaceError.existingBaseArtifactHashMismatch(expected: sha, actual: actual)
            }
        } else {
            try baseArtifactData.write(to: baseURL, options: [.atomic])
        }

        let memberOverlayURL = overlaysDirectory.appendingPathComponent("current.jsonl")
        if !fileManager.fileExists(atPath: memberOverlayURL.path) {
            fileManager.createFile(atPath: memberOverlayURL.path, contents: Data())
        }

        return KGWorkspace(
            rootURL: root,
            baseDirectoryURL: baseDirectory,
            memberOverlayURL: memberOverlayURL,
            opsDirectoryURL: opsDirectory,
            snapshotsDirectoryURL: snapshotsDirectory,
            receiptsDirectoryURL: receiptsDirectory,
            baseArtifactURL: baseURL,
            baseArtifactSHA256: sha
        )
    }

    public func loadBaseArtifact() throws -> GraphArtifact {
        try GraphArtifact.decode(from: Data(contentsOf: baseArtifactURL))
    }

    public static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

