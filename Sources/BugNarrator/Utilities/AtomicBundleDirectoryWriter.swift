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
        // The bundle is handed to the user, who usually puts it on the Desktop
        // or in Downloads -- directories that other accounts on a shared machine
        // can read. The bundle directory is created owner-only so nothing in it
        // is reachable by anyone else; the move into place keeps that mode.
        try fileManager.createDirectory(
            at: temporaryDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        do {
            try writeContents(temporaryDirectoryURL)
            try fileManager.moveItem(at: temporaryDirectoryURL, to: finalDirectoryURL)
            return finalDirectoryURL
        } catch {
            try? fileManager.removeItem(at: temporaryDirectoryURL)
            throw error
        }
    }

    /// Writes a file into a bundle so that only the owner can read it.
    ///
    /// The bundle ends up wherever the user picked -- typically the Desktop or
    /// Downloads of a shared machine -- so the files inside it are owner-only
    /// rather than readable by every local account.
    func writeOwnerOnly(_ contents: Data, to url: URL) throws {
        try contents.write(to: url, options: [.atomic])
        try restrictToOwner(url)
    }

    func writeOwnerOnly(_ contents: String, to url: URL) throws {
        try writeOwnerOnly(Data(contents.utf8), to: url)
    }

    /// Restricts a file that is already in place -- one copied in from the
    /// library, or streamed into the bundle -- to the owner.
    func restrictToOwner(_ url: URL) throws {
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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
