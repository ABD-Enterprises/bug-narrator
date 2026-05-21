import Combine
import Foundation

enum RecoveredRecordingImportOutcome: Equatable {
    case none
    case imported(message: String, error: AppError)
}

@MainActor
final class RecoveredRecordingImportController: ObservableObject {
    @Published private(set) var recoveredRecordingImportCount = 0

    private let transcriptStore: TranscriptStore
    private let sessionLibrary: SessionLibraryController
    private let recoveredRecordingImporter: any RecoveredRecordingImporting
    private let artifactsService: any SessionArtifactsManaging
    private let sessionLibraryLogger = DiagnosticsLogger(category: .sessionLibrary)

    init(
        transcriptStore: TranscriptStore,
        sessionLibrary: SessionLibraryController,
        recoveredRecordingImporter: any RecoveredRecordingImporting,
        artifactsService: any SessionArtifactsManaging
    ) {
        self.transcriptStore = transcriptStore
        self.sessionLibrary = sessionLibrary
        self.recoveredRecordingImporter = recoveredRecordingImporter
        self.artifactsService = artifactsService
    }

    func importRecoveredRecordingsAtLaunch() throws -> RecoveredRecordingImportOutcome {
        let importedCount = try recoveredRecordingImporter.importRecoverableRecordings(
            into: transcriptStore,
            artifactsService: artifactsService
        )
        recoveredRecordingImportCount = importedCount

        guard importedCount > 0 else {
            return .none
        }

        sessionLibrary.selectLatestPendingTranscriptionSession()
        sessionLibraryLogger.warning(
            "recovered_recordings_imported",
            "Imported recovered recordings as retryable transcript sessions.",
            metadata: ["imported_count": "\(importedCount)"]
        )

        let message = importedCount == 1
            ? "Recovered 1 recording after an unexpected quit. Open Session Library to transcribe it."
            : "Recovered \(importedCount) recordings after an unexpected quit. Open Session Library to transcribe them."
        return .imported(
            message: message,
            error: .transcriptionFailure("Recovered recordings are waiting for transcription.")
        )
    }
}

@MainActor
final class RecoveredRecordingLaunchImportPresenter {
    private let importController: RecoveredRecordingImportController
    private let errorPresenter: AppErrorPresenter
    private let sessionLibraryLogger: DiagnosticsLogger
    private let setStatus: (AppStatus, AppError?) -> Void
    private let openTranscriptHistory: () -> Void

    init(
        importController: RecoveredRecordingImportController,
        errorPresenter: AppErrorPresenter,
        sessionLibraryLogger: DiagnosticsLogger = DiagnosticsLogger(category: .sessionLibrary),
        setStatus: @escaping (AppStatus, AppError?) -> Void,
        openTranscriptHistory: @escaping () -> Void
    ) {
        self.importController = importController
        self.errorPresenter = errorPresenter
        self.sessionLibraryLogger = sessionLibraryLogger
        self.setStatus = setStatus
        self.openTranscriptHistory = openTranscriptHistory
    }

    func importRecoveredRecordingsAtLaunch() {
        do {
            let outcome = try importController.importRecoveredRecordingsAtLaunch()
            guard case .imported(let message, let error) = outcome else {
                return
            }

            setStatus(.error(message), error)
            openTranscriptHistory()
        } catch {
            let normalizedError = errorPresenter.normalizeError(
                error,
                operation: .recoveredRecordingImport,
                fallback: { .storageFailure($0) }
            )
            let appError = normalizedError.appError
            errorPresenter.logAppError(normalizedError, context: "recovered_recording_import_failed")
            sessionLibraryLogger.error(
                "recovered_recording_import_failed",
                appError.userMessage,
                metadata: errorPresenter.appErrorMetadata(for: normalizedError, context: "recovered_recording_import_failed")
            )
            setStatus(.error(appError.userMessage), appError)
        }
    }
}
