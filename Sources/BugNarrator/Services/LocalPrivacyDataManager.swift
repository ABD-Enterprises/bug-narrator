import Foundation

// Thread-safety invariant: all stored properties are immutable `let`s, so the
// value carries no mutable shared state. The `@unchecked` only suppresses the
// non-Sendable `FileManager`/recorder/store members; each of those is either
// independently thread-safe or confined to the store's own actor/queue, so
// sharing this value across tasks introduces no data race.
struct LocalPrivacyDataManager: @unchecked Sendable {
    private let fileManager: FileManager
    private let appSupportURL: URL
    private let telemetryRecorder: OperationalTelemetryRecorder
    private let diagnosticsStore: DiagnosticsLogStore

    init(
        fileManager: FileManager = .default,
        appSupportURL: URL = AppSupportLocation.appDirectory(fileManager: .default),
        telemetryRecorder: OperationalTelemetryRecorder = OperationalTelemetryRecorder(),
        diagnosticsStore: DiagnosticsLogStore = BugNarratorDiagnostics.store
    ) {
        self.fileManager = fileManager
        self.appSupportURL = appSupportURL
        self.telemetryRecorder = telemetryRecorder
        self.diagnosticsStore = diagnosticsStore
    }

    func clearLocalSupportArtifacts() async {
        try? telemetryRecorder.clear()
        await diagnosticsStore.clear()

        let removableURLs = [
            appSupportURL.appendingPathComponent("RecoveredRecordings", isDirectory: true),
            appSupportURL.appendingPathComponent("export-receipts.json", isDirectory: false),
            appSupportURL.appendingPathComponent("export-receipts.corrupt.json", isDirectory: false)
        ]

        for url in removableURLs where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
}

extension LocalPrivacyDataManager: LocalPrivacyDataManaging {}
