import Foundation
import os.log

enum AppSupportLocation {
    private static let currentAppDirectoryName = "BugNarrator"
    private static let fallbackDirectoryName = "BugNarrator-ApplicationSupportFallback"
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
        if let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return url
        }

        if let url = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            logFallbackSelection("caches")
            return url.appendingPathComponent(fallbackDirectoryName, isDirectory: true)
        }

        let homeURL = fileManager.homeDirectoryForCurrentUser
        if !homeURL.path.isEmpty, homeURL.path != "/" {
            logFallbackSelection("home")
            return homeURL.appendingPathComponent(fallbackDirectoryName, isDirectory: true)
        }

        logFallbackSelection("temporary")
        return fileManager.temporaryDirectory.appendingPathComponent(fallbackDirectoryName, isDirectory: true)
    }

    private static func logFallbackSelection(_ fallback: String) {
        let logger = Logger(subsystem: BugNarratorDiagnostics.subsystem, category: "app-support-location")
        logger.error("Application Support directory unavailable; using \(fallback, privacy: .public) fallback location.")
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
