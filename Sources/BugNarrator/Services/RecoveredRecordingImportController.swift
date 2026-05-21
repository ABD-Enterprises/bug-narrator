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
