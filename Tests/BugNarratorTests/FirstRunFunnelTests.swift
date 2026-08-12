import XCTest
@testable import BugNarrator

/// #959: a first-time DMG user hit a wall — recording was blocked until an AI
/// provider was configured, and the bundled sample had no route from the menu
/// bar, which is the only surface a new install shows.
final class FirstRunFunnelTests: XCTestCase {
    // MARK: - Recording without a provider

    /// The wall itself. Recording no longer depends on provider readiness; a
    /// stop without one preserves the session for later transcription.
    func testRecordingCanStartWithoutAConfiguredProvider() {
        XCTAssertTrue(FirstRunFunnel.canStartRecording(phaseAllowsStart: true))
    }

    func testRecordingStillCannotStartWhileBusy() {
        XCTAssertFalse(
            FirstRunFunnel.canStartRecording(phaseAllowsStart: false),
            "Recording and transcribing phases must still block a new start."
        )
    }

    /// Starting without a provider must be an informed choice, not a silent
    /// deferral — the user should know the audio is kept, not transcribed.
    func testStartWithoutProviderNoticeSaysTheSessionIsKept() {
        let notice = FirstRunFunnel.startWithoutProviderNotice(providerName: "OpenAI")

        XCTAssertTrue(notice.contains("OpenAI"), notice)
        XCTAssertTrue(notice.lowercased().contains("record"), notice)
        XCTAssertTrue(
            notice.lowercased().contains("transcribe"),
            "The notice must say transcription is what is deferred: \(notice)"
        )
    }

    /// The preserved-recording path this relies on already exists; if that
    /// mapping ever returned nil the recording would be dropped instead of
    /// kept, and the unblocked start would become data loss.
    func testAMissingProviderStopStillPreservesTheRecording() {
        XCTAssertEqual(
            PendingTranscriptionFailureReason(appError: .missingAPIKey),
            .missingAPIKey,
            "Recording without a provider is only safe because the stop is preserved as retryable."
        )
    }

    // MARK: - Sample reachability

    /// The gap: the sample shipped in #374 with a button in the session
    /// library's empty state, but a new install opens the menu bar, not that
    /// window.
    func testSampleIsOfferedWhenTheLibraryIsEmpty() {
        XCTAssertTrue(FirstRunFunnel.shouldOfferSampleSession(libraryIsEmpty: true))
    }

    func testSampleIsNotOfferedOnceRealSessionsExist() {
        XCTAssertFalse(
            FirstRunFunnel.shouldOfferSampleSession(libraryIsEmpty: false),
            "Once there is real history the offer is noise."
        )
    }

    /// The offer is only useful if the artifact behind it is real.
    func testTheOfferedSampleIsAUsableSession() {
        let sample = SampleSession.make()

        XCTAssertEqual(sample.id, SampleSession.id)
        XCTAssertTrue(sample.isSampleSession)
        XCTAssertFalse(sample.transcript.isEmpty)
        XCTAssertFalse(sample.issueExtraction?.issues.isEmpty ?? true)
    }

    // MARK: - Parakeet install path (#959)

    /// The free/local option was unobtainable from a DMG: every instruction
    /// named `local-transcription/venv/...`, a path only a source checkout has.
    /// The server is now published as a signed, notarized release asset.
    func testNoUserFacingGuidanceStillNamesTheSourceCheckoutPath() {
        let guidance = [
            AppError.networkFailure.userMessage(for: .parakeetLocal),
            AIProvider.parakeetLocal.baseURLHint
        ]

        for message in guidance {
            XCTAssertFalse(
                message.contains("local-transcription/venv"),
                "A DMG user has no such path: \(message)"
            )
        }
    }

    func testTheLocalTranscriptionDownloadPointsAtReleases() {
        XCTAssertTrue(
            BugNarratorLinks.localTranscriptionDownload.absoluteString.contains("releases"),
            BugNarratorLinks.localTranscriptionDownload.absoluteString
        )
    }

    /// The offline error is the message a user actually hits when the server is
    /// not running, so it has to name how to get it.
    func testTheOfflineMessageTellsTheUserWhereToGetTheServer() {
        let message = AppError.networkFailure.userMessage(for: .parakeetLocal)

        XCTAssertTrue(message.lowercased().contains("download"), message)
        XCTAssertTrue(message.contains("bugnarrator-transcription"), message)
    }

}
