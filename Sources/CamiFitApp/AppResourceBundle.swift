import Foundation

enum AppResourceBundle {
    private static let bundleName = "CamiFit_CamiFitApp.bundle"

    static func url(forResource name: String, withExtension ext: String?, subdirectory: String? = nil) -> URL? {
        bundle?.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
    }

    static func directory(named name: String) -> URL? {
        bundle?.url(forResource: name, withExtension: nil)
    }

    private static var bundle: Bundle? {
        if let packagedBundle = candidateURLs().lazy.compactMap({ Bundle(url: $0) }).first {
            return packagedBundle
        }
        guard Bundle.main.bundleURL.pathExtension != "app" else {
            return nil
        }
        return Bundle.module
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []
        let main = Bundle.main

        if let resourceURL = main.resourceURL {
            appendBundleCandidates(startingAt: resourceURL, to: &urls)
        }
        appendBundleCandidates(startingAt: main.bundleURL, to: &urls)
        if let executableDirectory = main.executableURL?.deletingLastPathComponent() {
            appendBundleCandidates(startingAt: executableDirectory, to: &urls)
        }

        return urls
    }

    private static func appendBundleCandidates(startingAt startURL: URL, to urls: inout [URL]) {
        var current = startURL
        for _ in 0..<8 {
            urls.append(current.appendingPathComponent(bundleName, isDirectory: true))
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { break }
            current = parent
        }
    }
}
