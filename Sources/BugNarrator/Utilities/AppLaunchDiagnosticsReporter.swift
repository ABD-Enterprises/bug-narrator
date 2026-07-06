import OSLog
import Foundation

@MainActor
final class AppLaunchDiagnosticsReporter {
    private let permissionRecoveryController: PermissionRecoveryController
    private let transcriptStore: TranscriptStore
    private let sessionLibraryLogger: DiagnosticsLogger

    init(
        permissionRecoveryController: PermissionRecoveryController,
        transcriptStore: TranscriptStore,
        sessionLibraryLogger: DiagnosticsLogger = DiagnosticsLogger(category: .sessionLibrary)
    ) {
        self.permissionRecoveryController = permissionRecoveryController
        self.transcriptStore = transcriptStore
        self.sessionLibraryLogger = sessionLibraryLogger
    }

    func logLaunchDiagnostics(selectedTranscriptID: UUID?) {
        permissionRecoveryController.logLaunchPermissionSnapshot()

        sessionLibraryLogger.info(
            "launch_session_store_snapshot",
            "Captured the initial session library state at launch.",
            metadata: [
                "stored_session_count": "\(transcriptStore.sessionCount)",
                "selected_transcript_id": selectedTranscriptID?.uuidString ?? "none"
            ]
        )
    }
}
