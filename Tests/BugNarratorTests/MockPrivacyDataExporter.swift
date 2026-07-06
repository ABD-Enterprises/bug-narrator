import Foundation
@testable import BugNarrator

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

