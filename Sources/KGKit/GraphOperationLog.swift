import Foundation

public struct GraphOperationLog {
    public enum LogError: Error, Equatable {
        case corruptLine(Int)
    }

    public let url: URL
    private let fileManager: FileManager

    public init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    public func readOperations() throws -> [GraphOperation] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true)
        let decoder = JSONDecoder()
        return try lines.enumerated().map { index, line in
            guard let lineData = String(line).data(using: .utf8) else {
                throw LogError.corruptLine(index + 1)
            }
            return try decoder.decode(GraphOperation.self, from: lineData)
        }
    }

    public func revision() throws -> Int {
        try readOperations().count
    }

    @discardableResult
    public func append(_ operation: GraphOperation, validator: OverlayValidator) throws -> Int {
        let currentRevision = try revision()
        try validator.validate(operation, currentRevision: currentRevision)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: Data())
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(operation)
        data.append(0x0A)

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        return currentRevision + 1
    }
}

