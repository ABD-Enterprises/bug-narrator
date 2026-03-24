import Foundation

struct SessionArtifactsService: SessionArtifactsManaging {
    private let fileManager: FileManager
    private let rootDirectoryURL: URL
    private let logger = DiagnosticsLogger(category: .sessionLibrary)

    init(fileManager: FileManager = .default, rootDirectoryURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootDirectoryURL = rootDirectoryURL ?? AppSupportLocation.appDirectory(fileManager: fileManager)
            .appendingPathComponent("SessionAssets", isDirectory: true)

        if !fileManager.fileExists(atPath: self.rootDirectoryURL.path) {
            try? fileManager.createDirectory(at: self.rootDirectoryURL, withIntermediateDirectories: true)
        }
    }

    func createArtifactsDirectory(for sessionID: UUID) throws -> URL {
        let directoryURL = rootDirectoryURL.appendingPathComponent(sessionID.uuidString, isDirectory: true)

        if fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.removeItem(at: directoryURL)
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        logger.debug(
            "artifacts_directory_created",
            "Prepared a session artifacts directory.",
            metadata: ["session_id": sessionID.uuidString]
        )
        return directoryURL
    }

    func makeRecordedAudioURL(
        in directoryURL: URL,
        sourceFileURL: URL
    ) -> URL {
        let fileExtension = sourceFileURL.pathExtension.isEmpty ? "m4a" : sourceFileURL.pathExtension
        return directoryURL
            .appendingPathComponent("recording")
            .appendingPathExtension(fileExtension)
    }

    func makeScreenshotURL(
        in directoryURL: URL,
        prefix: String,
        index: Int,
        elapsedTime: TimeInterval
    ) -> URL {
        let formattedElapsed = ElapsedTimeFormatter.string(from: elapsedTime).replacingOccurrences(of: ":", with: "-")
        let sanitizedPrefix = sanitizeFileNameComponent(prefix)
        return directoryURL
            .appendingPathComponent("\(sanitizedPrefix)-\(index)-\(formattedElapsed)")
            .appendingPathExtension("png")
    }

    func removeArtifactsDirectory(at directoryURL: URL) {
        guard isManagedArtifactsDirectory(directoryURL) else {
            logger.warning(
                "artifacts_directory_rejected",
                "Skipped cleanup for a directory outside BugNarrator-managed artifacts storage.",
                metadata: ["directory_name": directoryURL.lastPathComponent]
            )
            return
        }

        try? fileManager.removeItem(at: directoryURL)
        logger.debug(
            "artifacts_directory_removed",
            "Removed a BugNarrator-managed artifacts directory.",
            metadata: ["directory_name": directoryURL.lastPathComponent]
        )
    }

    private func sanitizeFileNameComponent(_ value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

        let normalized = String(trimmedValue.unicodeScalars.map { scalar in
            if allowedCharacters.contains(scalar) {
                return Character(scalar)
            }

            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return "-"
            }

            return "-"
        })

        let collapsed = normalized
            .components(separatedBy: CharacterSet(charactersIn: "-"))
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return collapsed.isEmpty ? "capture" : collapsed
    }

    private func isManagedArtifactsDirectory(_ directoryURL: URL) -> Bool {
        let standardizedDirectoryURL = directoryURL.standardizedFileURL
        let standardizedRootURL = rootDirectoryURL.standardizedFileURL

        guard standardizedDirectoryURL != standardizedRootURL else {
            return false
        }

        return standardizedDirectoryURL.path.hasPrefix(standardizedRootURL.path + "/")
    }
}
