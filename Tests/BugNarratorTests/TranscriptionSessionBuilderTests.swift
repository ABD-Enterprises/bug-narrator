import XCTest
@testable import BugNarrator

final class TranscriptionSessionBuilderTests: XCTestCase {
    func testCompletedSessionPreservesRecordingContextAndBuildsSections() {
        let screenshotID = UUID()
        let marker = SessionMarker(
            id: UUID(),
            index: 1,
            elapsedTime: 4,
            createdAt: Date(timeIntervalSince1970: 90),
            title: "Opened command center",
            note: "Refresh crashed",
            screenshotID: screenshotID
        )
        let screenshot = SessionScreenshot(
            id: screenshotID,
            createdAt: Date(timeIntervalSince1970: 95),
            elapsedTime: 5,
            filePath: "/tmp/command-center.png",
            associatedMarkerID: marker.id
        )
        let recordingSession = RecordingSessionDraft(
            sessionID: UUID(),
            artifactsDirectoryURL: URL(fileURLWithPath: "/tmp/session-artifacts", isDirectory: true),
            markers: [marker],
            screenshots: [screenshot]
        )
        let recordedAudio = RecordedAudio(
            fileURL: URL(fileURLWithPath: "/tmp/recording.m4a"),
            duration: 10
        )
        let request = TranscriptionRequest(
            model: "whisper-1",
            languageHint: "en",
            prompt: "Focus on tester narration."
        )
        let qualityFinding = TranscriptQualityFinding(
            kind: .abruptEnding,
            severity: .warning,
            message: "Transcript may end abruptly."
        )
        let result = TranscriptionResult(
            text: "The refresh button crashed after opening command center.",
            segments: [
                TranscriptionSegment(start: 0, end: 3, text: "The refresh button crashed"),
                TranscriptionSegment(start: 4, end: 8, text: "after opening command center.")
            ],
            qualityFindings: [qualityFinding]
        )
        let createdAt = Date(timeIntervalSince1970: 100)

        let session = TranscriptionSessionBuilder.completedSession(
            from: recordingSession,
            recordedAudio: recordedAudio,
            request: request,
            result: result,
            createdAt: createdAt
        )

        XCTAssertEqual(session.id, recordingSession.sessionID)
        XCTAssertEqual(session.createdAt, createdAt)
        XCTAssertEqual(session.updatedAt, createdAt)
        XCTAssertEqual(session.transcript, result.text)
        XCTAssertEqual(session.duration, recordedAudio.duration)
        XCTAssertEqual(session.model, request.model)
        XCTAssertEqual(session.languageHint, request.languageHint)
        XCTAssertEqual(session.prompt, request.prompt)
        XCTAssertEqual(session.markers, [marker])
        XCTAssertEqual(session.screenshots, [screenshot])
        XCTAssertEqual(session.transcriptQualityFindings, [qualityFinding])
        XCTAssertEqual(session.artifactsDirectoryPath, recordingSession.artifactsDirectoryURL.path)
        XCTAssertNil(session.issueExtraction)
        XCTAssertNil(session.pendingTranscription)
        XCTAssertEqual(session.sections.count, 2)
        XCTAssertEqual(session.sections.last?.markerID, marker.id)
        XCTAssertEqual(session.sections.last?.screenshotIDs, [screenshotID])
    }

    func testRecoveredSessionPreservesRecoverableContextAndClearsRetryState() {
        let originalID = UUID()
        let originalCreatedAt = Date(timeIntervalSince1970: 50)
        let marker = SessionMarker(
            index: 1,
            elapsedTime: 2,
            title: "Retry point",
            screenshotID: nil
        )
        let original = TranscriptSession(
            id: originalID,
            createdAt: originalCreatedAt,
            transcript: "",
            duration: 8,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            markers: [marker],
            screenshots: [],
            issueExtraction: IssueExtractionResult(
                summary: "Old extracted issue summary",
                issues: []
            ),
            pendingTranscription: PendingTranscription(
                audioFileName: "recording.m4a",
                failureReason: .missingAPIKey,
                preservedAt: Date(timeIntervalSince1970: 60)
            ),
            recoveredSourceFileName: "crash-recovery-recording.m4a",
            artifactsDirectoryPath: "/tmp/recovered-session"
        )
        let request = TranscriptionRequest(
            model: "gpt-4o-transcribe",
            languageHint: "en",
            prompt: "Recovered session prompt"
        )
        let qualityFinding = TranscriptQualityFinding(
            kind: .shortTranscript,
            severity: .warning,
            message: "Short transcript."
        )
        let result = TranscriptionResult(
            text: "Recovered retry transcript.",
            segments: [],
            qualityFindings: [qualityFinding]
        )

        let session = TranscriptionSessionBuilder.recoveredSession(
            from: original,
            request: request,
            result: result
        )

        XCTAssertEqual(session.id, originalID)
        XCTAssertEqual(session.createdAt, originalCreatedAt)
        XCTAssertGreaterThanOrEqual(session.updatedAt, originalCreatedAt)
        XCTAssertEqual(session.transcript, result.text)
        XCTAssertEqual(session.duration, original.duration)
        XCTAssertEqual(session.model, request.model)
        XCTAssertEqual(session.languageHint, request.languageHint)
        XCTAssertEqual(session.prompt, request.prompt)
        XCTAssertEqual(session.markers, original.markers)
        XCTAssertEqual(session.screenshots, original.screenshots)
        XCTAssertEqual(session.transcriptQualityFindings, [qualityFinding])
        XCTAssertNil(session.recoveredSourceFileName)
        XCTAssertEqual(session.artifactsDirectoryPath, original.artifactsDirectoryPath)
        XCTAssertNil(session.issueExtraction)
        XCTAssertNil(session.pendingTranscription)
        XCTAssertEqual(session.sections.last?.title, marker.title)
    }

    func testRetryableSessionPreservesRecordingContextAndPendingTranscriptionMetadata() {
        let screenshotID = UUID()
        let marker = SessionMarker(
            index: 1,
            elapsedTime: 3,
            title: "Failure point",
            screenshotID: screenshotID
        )
        let screenshot = SessionScreenshot(
            id: screenshotID,
            elapsedTime: 3,
            filePath: "/tmp/failure-point.png",
            associatedMarkerID: marker.id
        )
        let recordingSession = RecordingSessionDraft(
            sessionID: UUID(),
            artifactsDirectoryURL: URL(fileURLWithPath: "/tmp/retry-artifacts", isDirectory: true),
            markers: [marker],
            screenshots: [screenshot]
        )
        let recordedAudio = RecordedAudio(
            fileURL: URL(fileURLWithPath: "/tmp/original-recording.m4a"),
            duration: 12
        )
        let request = TranscriptionRequest(
            model: "whisper-1",
            languageHint: "en",
            prompt: "Retry later"
        )
        let preservedAudioURL = URL(fileURLWithPath: "/tmp/retry-artifacts/preserved-recording.m4a")
        let createdAt = Date(timeIntervalSince1970: 200)
        let preservedAt = Date(timeIntervalSince1970: 205)

        let session = TranscriptionSessionBuilder.retryableSession(
            from: recordingSession,
            recordedAudio: recordedAudio,
            request: request,
            failureReason: .missingAPIKey,
            preservedAudioURL: preservedAudioURL,
            createdAt: createdAt,
            preservedAt: preservedAt
        )

        XCTAssertEqual(session.id, recordingSession.sessionID)
        XCTAssertEqual(session.createdAt, createdAt)
        XCTAssertEqual(session.updatedAt, createdAt)
        XCTAssertEqual(session.transcript, "")
        XCTAssertEqual(session.duration, recordedAudio.duration)
        XCTAssertEqual(session.model, request.model)
        XCTAssertEqual(session.languageHint, request.languageHint)
        XCTAssertEqual(session.prompt, request.prompt)
        XCTAssertEqual(session.markers, [marker])
        XCTAssertEqual(session.screenshots, [screenshot])
        XCTAssertTrue(session.sections.isEmpty)
        XCTAssertNil(session.issueExtraction)
        XCTAssertEqual(session.pendingTranscription?.audioFileName, preservedAudioURL.lastPathComponent)
        XCTAssertEqual(session.pendingTranscription?.failureReason, .missingAPIKey)
        XCTAssertEqual(session.pendingTranscription?.preservedAt, preservedAt)
        XCTAssertEqual(session.artifactsDirectoryPath, recordingSession.artifactsDirectoryURL.path)
    }
}
