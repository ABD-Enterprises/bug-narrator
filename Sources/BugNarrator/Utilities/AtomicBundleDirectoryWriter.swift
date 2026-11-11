import Foundation

struct AtomicBundleDirectoryWriter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func writeBundle(
        in baseDirectory: URL,
        suggestedName: String,
        writeContents: (URL) throws -> Void
    ) throws -> URL {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }

        let finalDirectoryURL = uniqueBundleDirectoryURL(
            baseDirectory: baseDirectory,
            suggestedName: suggestedName
        )
        let temporaryDirectoryURL = baseDirectory
            .appendingPathComponent(".\(suggestedName)-\(UUID().uuidString).tmp", isDirectory: true)

        try? fileManager.removeItem(at: temporaryDirectoryURL)
        try fileManager.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])

        do {
            try writeContents(temporaryDirectoryURL)
            try restrictBundlePermissions(at: temporaryDirectoryURL)
            try fileManager.moveItem(at: temporaryDirectoryURL, to: finalDirectoryURL)
            return finalDirectoryURL
        } catch {
            try? fileManager.removeItem(at: temporaryDirectoryURL)
            throw error
        }
    }

    private func restrictBundlePermissions(at directory: URL) throws {
        for child in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let attributes = try fileManager.attributesOfItem(atPath: child.path)
            switch attributes[.type] as? FileAttributeType {
            case .typeDirectory:
                try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: child.path)
                try restrictBundlePermissions(at: child)
            case .typeRegular:
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: child.path)
            default:
                // Never follow a link out of the private staging directory.
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }

    func uniqueBundleDirectoryURL(baseDirectory: URL, suggestedName: String) -> URL {
        var candidateURL = baseDirectory.appendingPathComponent(suggestedName, isDirectory: true)
        var suffix = 2

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateURL = baseDirectory.appendingPathComponent("\(suggestedName)-\(suffix)", isDirectory: true)
            suffix += 1
        }

        return candidateURL
    }
}
