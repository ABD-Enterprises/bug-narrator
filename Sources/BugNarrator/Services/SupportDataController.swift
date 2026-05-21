import Foundation

struct DebugInfoCopyResult {
    let snapshot: DebugInfoSnapshot
    let statusMessage: String
}

struct DebugBundleExportCompletion {
    let bundleURL: URL
    let statusMessage: String
}

struct PrivacyDataExportCompletion {
    let bundleURL: URL
    let statusMessage: String
}

@MainActor
final class SupportDataActionPresenter {
    private let setStatus: (AppStatus) -> Void
    private let revealInFinder: (URL) -> AppUtilityActionResult
    private let presentUtilityActionResult: (AppUtilityActionResult) -> Void
    private let presentDeletionFailure: (Error) -> Void

    init(
        setStatus: @escaping (AppStatus) -> Void,
        revealInFinder: @escaping (URL) -> AppUtilityActionResult,
        presentUtilityActionResult: @escaping (AppUtilityActionResult) -> Void,
        presentDeletionFailure: @escaping (Error) -> Void = { _ in }
    ) {
        self.setStatus = setStatus
        self.revealInFinder = revealInFinder
        self.presentUtilityActionResult = presentUtilityActionResult
        self.presentDeletionFailure = presentDeletionFailure
    }

    convenience init(
        presentationState: AppPresentationState,
        errorPresenter: AppErrorPresenter,
        utilityActions: AppUtilityActionController,
        utilityResultPresenter: AppUtilityActionResultPresenter
    ) {
        self.init(
            setStatus: { status in
                presentationState.setStatus(status, error: nil)
            },
            revealInFinder: { url in
                utilityActions.revealInFinder(url)
            },
            presentUtilityActionResult: { result in
                utilityResultPresenter.present(result)
            },
            presentDeletionFailure: { error in
                _ = errorPresenter.presentError(error, operation: .sessionLibrary, fallback: { .storageFailure($0) })
            }
        )
    }

    func presentCopyDebugInfo(_ result: DebugInfoCopyResult) {
        presentSuccess(result.statusMessage)
    }

    func presentDebugBundleExport(_ completion: DebugBundleExportCompletion) {
        presentExportedBundle(at: completion.bundleURL, statusMessage: completion.statusMessage)
    }

    func presentPrivacyDataExport(_ completion: PrivacyDataExportCompletion) {
        presentExportedBundle(at: completion.bundleURL, statusMessage: completion.statusMessage)
    }

    func presentLocalDataDeletion(_ outcome: LocalDataDeletionOutcome) {
        presentSuccess(outcome.statusMessage)
    }

    func presentLocalDataDeletion(_ result: LocalDataDeletionResult) {
        switch result {
        case .blocked(let message):
            setStatus(.error(message))
        case .deleted(let outcome):
            presentLocalDataDeletion(outcome)
        }
    }

    func presentLocalDataDeletionFailure(_ error: Error) {
        presentDeletionFailure(error)
    }

    private func presentExportedBundle(at bundleURL: URL, statusMessage: String) {
        presentUtilityActionResult(revealInFinder(bundleURL))
        presentSuccess(statusMessage)
    }

    private func presentSuccess(_ message: String) {
        setStatus(.success(message))
    }
}

@MainActor
final class SupportDataController {
    private let settingsStore: SettingsStore
    private let transcriptStore: TranscriptStore
    private let exportService: any IssueExporting
    private let clipboardService: any ClipboardWriting
    private let debugBundleExporter: any DebugBundleExporting
    private let privacyDataExporter: any PrivacyDataExporting
    private let telemetryRecorder: any OperationalTelemetryRecording
    private let localPrivacyDataManager: any LocalPrivacyDataManaging
    private let settingsLogger = DiagnosticsLogger(category: .settings)
    private let sessionLibraryLogger = DiagnosticsLogger(category: .sessionLibrary)

    init(
        settingsStore: SettingsStore,
        transcriptStore: TranscriptStore,
        exportService: any IssueExporting,
        clipboardService: any ClipboardWriting,
        debugBundleExporter: any DebugBundleExporting,
        privacyDataExporter: any PrivacyDataExporting,
        telemetryRecorder: any OperationalTelemetryRecording,
        localPrivacyDataManager: any LocalPrivacyDataManaging
    ) {
        self.settingsStore = settingsStore
        self.transcriptStore = transcriptStore
        self.exportService = exportService
        self.clipboardService = clipboardService
        self.debugBundleExporter = debugBundleExporter
        self.privacyDataExporter = privacyDataExporter
        self.telemetryRecorder = telemetryRecorder
        self.localPrivacyDataManager = localPrivacyDataManager
    }

    func debugInfoSnapshot(sessionID: UUID?) -> DebugInfoSnapshot {
        DebugInfoSnapshot(
            metadata: BugNarratorMetadata(),
            settingsStore: settingsStore,
            sessionID: sessionID
        )
    }

    func copyDebugInfo(sessionID: UUID?) -> DebugInfoCopyResult {
        let snapshot = debugInfoSnapshot(sessionID: sessionID)
        clipboardService.copy(snapshot.clipboardText)
        settingsLogger.info(
            "debug_info_copied",
            "Copied debug info to the clipboard.",
            metadata: ["session_id": snapshot.sessionID?.uuidString ?? "none"]
        )
        return DebugInfoCopyResult(
            snapshot: snapshot,
            statusMessage: "Debug info copied to the clipboard."
        )
    }

    func exportDebugBundle(
        sessionMetadata: DebugSessionMetadata
    ) async throws -> DebugBundleExportCompletion? {
        let snapshot = DebugBundleSnapshot(
            debugInfo: debugInfoSnapshot(sessionID: sessionMetadata.sessionID),
            sessionMetadata: sessionMetadata,
            recentLogText: await BugNarratorDiagnostics.recentLogText()
        )

        guard let bundleURL = try debugBundleExporter.export(snapshot: snapshot) else {
            return nil
        }

        settingsLogger.info(
            "debug_bundle_exported",
            "Exported a local debug bundle.",
            metadata: [
                "session_id": snapshot.sessionMetadata.sessionID?.uuidString ?? "none",
                "debug_mode": snapshot.debugInfo.debugModeEnabled ? "enabled" : "disabled"
            ]
        )

        return DebugBundleExportCompletion(
            bundleURL: bundleURL,
            statusMessage: settingsStore.debugMode
                ? "Debug bundle exported with verbose diagnostics."
                : "Debug bundle exported."
        )
    }

    func exportPrivacyData(
        exportHistoryFallback: [ExportReceipt]
    ) async throws -> PrivacyDataExportCompletion? {
        let diagnostics = await makePrivacyDataExportDiagnosticsSnapshot(
            exportHistoryFallback: exportHistoryFallback
        )
        let sessions = transcriptStore.allStoredSessions()

        guard let bundleURL = try privacyDataExporter.export(
            sessions: sessions,
            settings: makePrivacyDataExportSettingsSnapshot(),
            diagnostics: diagnostics
        ) else {
            return nil
        }

        let sessionCount = transcriptStore.sessionCount
        sessionLibraryLogger.info(
            "privacy_data_exported",
            "Exported a local privacy data bundle.",
            metadata: ["session_count": "\(sessionCount)"]
        )
        telemetryRecorder.record(
            .privacyDataExported,
            metadata: ["session_count": "\(sessionCount)"]
        )

        return PrivacyDataExportCompletion(
            bundleURL: bundleURL,
            statusMessage: "Data export created. API keys and tracker credentials were not included."
        )
    }

    func clearLocalPrivacyArtifacts() async {
        await localPrivacyDataManager.clearLocalSupportArtifacts()
    }

    private func makePrivacyDataExportSettingsSnapshot() -> PrivacyDataExportSettingsSnapshot {
        PrivacyDataExportSettingsSnapshot(settingsStore: settingsStore)
    }

    private func makePrivacyDataExportDiagnosticsSnapshot(
        exportHistoryFallback: [ExportReceipt]
    ) async -> PrivacyDataExportDiagnosticsSnapshot {
        let debugInfo = debugInfoSnapshot(sessionID: nil)
        let recentLogText = await BugNarratorDiagnostics.store.recentLogText(limit: 200)
        let receipts = (try? await exportService.exportHistory()) ?? exportHistoryFallback

        return PrivacyDataExportDiagnosticsSnapshot(
            appName: debugInfo.appName,
            versionDescription: debugInfo.versionDescription,
            macOSVersion: debugInfo.macOSVersion,
            architecture: debugInfo.architecture,
            activeTranscriptionModel: debugInfo.activeTranscriptionModel,
            issueExtractionModel: debugInfo.issueExtractionModel,
            logLevel: debugInfo.logLevel,
            debugModeEnabled: debugInfo.debugModeEnabled,
            recentTelemetryEvents: telemetryRecorder.recentEvents(limit: 200),
            recentDiagnosticsLog: recentLogText,
            exportHistory: receipts
        )
    }
}
