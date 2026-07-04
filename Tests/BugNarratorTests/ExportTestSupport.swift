import Foundation
@testable import BugNarrator

final class MockArtifactsService: SessionArtifactsManaging {
    private let fileManager: FileManager
    private let rootDirectoryURL: URL

    private(set) var createdDirectories: [URL] = []
    private(set) var removedDirectories: [URL] = []

    init(rootDirectoryURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootDirectoryURL = rootDirectoryURL
        try? fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
    }

    func createArtifactsDirectory(for sessionID: UUID) throws -> URL {
        let directoryURL = rootDirectoryURL.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        createdDirectories.append(directoryURL)
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
        directoryURL.appendingPathComponent("\(prefix)-\(index)").appendingPathExtension("png")
    }

    func removeArtifactsDirectory(at directoryURL: URL) {
        removedDirectories.append(directoryURL)
        try? fileManager.removeItem(at: directoryURL)
    }
}

final class MockClipboardService: ClipboardWriting {
    private(set) var copiedStrings: [String] = []

    func copy(_ string: String) {
        copiedStrings.append(string)
    }
}

@MainActor
final class MockDebugBundleExporter: DebugBundleExporting {
    var exportResult: Result<URL?, Error> = .success(nil)
    private(set) var exportedSnapshots: [DebugBundleSnapshot] = []

    func export(snapshot: DebugBundleSnapshot) throws -> URL? {
        exportedSnapshots.append(snapshot)
        return try exportResult.get()
    }
}

@MainActor
final class MockPrivacyDataExporter: PrivacyDataExporting {
    struct ExportRequest {
        let sessions: [TranscriptSession]
        let settings: PrivacyDataExportSettingsSnapshot
        let diagnostics: PrivacyDataExportDiagnosticsSnapshot
    }

    var exportResult: Result<URL?, Error> = .success(nil)
    private(set) var exportRequests: [ExportRequest] = []

    func export(
        sessions: PrivacyDataSessionStream,
        settings: PrivacyDataExportSettingsSnapshot,
        diagnostics: PrivacyDataExportDiagnosticsSnapshot
    ) throws -> URL? {
        // Materialize the lazy stream so existing assertions on the requested
        // sessions keep working.
        var materialized: [TranscriptSession] = []
        try sessions.forEach { materialized.append($0) }
        exportRequests.append(
            ExportRequest(
                sessions: materialized,
                settings: settings,
                diagnostics: diagnostics
            )
        )
        return try exportResult.get()
    }
}

