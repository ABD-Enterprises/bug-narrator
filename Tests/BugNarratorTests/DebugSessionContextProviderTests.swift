import XCTest
@testable import BugNarrator

final class DebugSessionContextProviderTests: XCTestCase {
    func testCurrentSessionIDPrefersActiveRecordingSession() {
        let activeSession = RecordingSessionDraft(
            sessionID: UUID(),
            artifactsDirectoryURL: FileManager.default.temporaryDirectory
        )
        let displayedTranscript = makeSampleTranscriptSession(index: 2)
        let currentTranscript = makeSampleTranscriptSession(index: 3)

        let sessionID = DebugSessionContextProvider.currentSessionID(
            activeRecordingSession: activeSession,
            displayedTranscript: displayedTranscript,
            currentTranscript: currentTranscript
        )

        XCTAssertEqual(sessionID, activeSession.sessionID)
    }

    func testCurrentSessionIDPrefersDisplayedTranscriptOverCurrentTranscript() {
        let displayedTranscript = makeSampleTranscriptSession(index: 2)
        let currentTranscript = makeSampleTranscriptSession(index: 3)

        let sessionID = DebugSessionContextProvider.currentSessionID(
            activeRecordingSession: nil,
            displayedTranscript: displayedTranscript,
            currentTranscript: currentTranscript
        )

        XCTAssertEqual(sessionID, displayedTranscript.id)
    }

    func testCurrentSessionIDFallsBackToCurrentTranscript() {
        let currentTranscript = makeSampleTranscriptSession(index: 3)

        let sessionID = DebugSessionContextProvider.currentSessionID(
            activeRecordingSession: nil,
            displayedTranscript: nil,
            currentTranscript: currentTranscript
        )

        XCTAssertEqual(sessionID, currentTranscript.id)
    }

    func testMetadataPreservesStatusErrorAndTranscriptContext() {
        let displayedTranscript = makeSampleTranscriptSession(index: 2)

        let metadata = DebugSessionContextProvider.metadata(
            currentTranscript: makeSampleTranscriptSession(index: 3),
            displayedTranscript: displayedTranscript,
            activeRecordingSession: nil,
            status: .error("Support export failed."),
            currentError: .missingAPIKey
        )

        XCTAssertEqual(metadata.source, .transcript)
        XCTAssertEqual(metadata.sessionID, displayedTranscript.id)
        XCTAssertEqual(metadata.statusDetail, "Support export failed.")
        XCTAssertEqual(metadata.errorMessage, AppError.missingAPIKey.userMessage)
        XCTAssertEqual(metadata.transcriptCharacterCount, displayedTranscript.transcript.count)
    }

    func testMetadataUsesActiveRecordingContextWhenPresent() {
        let activeSession = RecordingSessionDraft(
            sessionID: UUID(),
            artifactsDirectoryURL: FileManager.default.temporaryDirectory
        )

        let metadata = DebugSessionContextProvider.metadata(
            currentTranscript: makeSampleTranscriptSession(index: 3),
            displayedTranscript: makeSampleTranscriptSession(index: 2),
            activeRecordingSession: activeSession,
            status: .recording("Recording in progress."),
            currentError: nil
        )

        XCTAssertEqual(metadata.source, .activeRecording)
        XCTAssertEqual(metadata.sessionID, activeSession.sessionID)
        XCTAssertEqual(metadata.statusDetail, "Recording in progress.")
        XCTAssertNil(metadata.errorMessage)
        XCTAssertNil(metadata.transcriptCharacterCount)
    }
}
