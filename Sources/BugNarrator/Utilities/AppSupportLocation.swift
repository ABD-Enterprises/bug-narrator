import Foundation

enum AppSupportLocation {
    private static let currentAppDirectoryName = "BugNarrator"
    private static let legacyAppDirectoryNames = ["SessionMic"]

    static func appDirectory(fileManager: FileManager = .default) -> URL {
        let baseURL = applicationSupportBaseURL(fileManager: fileManager)
        let currentDirectoryURL = baseURL.appendingPathComponent(currentAppDirectoryName, isDirectory: true)

        migrateLegacyDirectoryIfNeeded(
            fileManager: fileManager,
            baseURL: baseURL,
            currentDirectoryURL: currentDirectoryURL
        )

        if !fileManager.fileExists(atPath: currentDirectoryURL.path) {
            try? fileManager.createDirectory(at: currentDirectoryURL, withIntermediateDirectories: true)
        }

        return currentDirectoryURL
    }

    private static func applicationSupportBaseURL(fileManager: FileManager) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ??
            fileManager.temporaryDirectory.appendingPathComponent(
                "\(currentAppDirectoryName)-ApplicationSupportFallback",
                isDirectory: true
            )
    }

    private static func migrateLegacyDirectoryIfNeeded(
        fileManager: FileManager,
        baseURL: URL,
        currentDirectoryURL: URL
    ) {
        guard !fileManager.fileExists(atPath: currentDirectoryURL.path) else {
            return
        }

        for legacyName in legacyAppDirectoryNames {
            let legacyDirectoryURL = baseURL.appendingPathComponent(legacyName, isDirectory: true)
            guard fileManager.fileExists(atPath: legacyDirectoryURL.path) else {
                continue
            }

            try? fileManager.moveItem(at: legacyDirectoryURL, to: currentDirectoryURL)
            return
        }
    }
}
