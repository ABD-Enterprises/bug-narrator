import Foundation
import XCTest
@testable import BugNarrator

/// #1015: a stop that failed with `.transcriptionFailure` deleted the user's
/// recording and screenshots instead of preserving them for retry.
///
/// The asymmetry was the tell: a dropped network preserved the session, a
/// malformed provider body destroyed it — and the malformed body is the more
/// likely failure for the local models #956 exists to support.
@MainActor
final class StopFailurePreservationTests: XCTestCase {

    /// Every AppError that can end a stop with audio still on disk must map to
    /// a preserve reason. An unmapped one reaches `default: return nil`, and
    /// `handleStopSessionFailure` then calls `removeArtifactsDirectory`.
    func testEveryRecoverableStopFailurePreservesTheRecording() {
        let recoverable: [(String, AppError)] = [
            ("generic transcription failure", .transcriptionFailure("the server returned an unparseable body")),
            ("missing credential", .missingAPIKey),
            ("invalid credential", .invalidAPIKey),
            ("revoked credential", .revokedAPIKey),
            ("network timeout", .networkTimeout),
            ("network failure", .networkFailure),
            ("rate limited", .rateLimited(retryAfter: nil)),
            ("spent account", .providerQuotaExhausted),
            ("provider rejected the request", .openAIRequestRejected("bad request")),
            ("empty transcript", .emptyTranscript)
        ]

        for (label, error) in recoverable {
            XCTAssertNotNil(
                TranscriptionRecoveryController.preservableStopFailureReason(for: error),
                "\(label) must preserve the recording; an unmapped reason deletes the audio and screenshots."
            )
        }
    }

    /// The specific regression, named.
    func testGenericTranscriptionFailureIsPreservedNotDeleted() {
        XCTAssertEqual(
            TranscriptionRecoveryController.preservableStopFailureReason(for: AppError.transcriptionFailure("unparseable response")),
            .transcriptionFailure
        )
    }

    /// The reason case shipped with retry copy written for it while being
    /// unreachable from any AppError. Round-tripping proves it is wired now.
    func testTheReasonRoundTripsAndCarriesItsRetryCopy() {
        let reason = TranscriptionRecoveryController.preservableStopFailureReason(for: AppError.transcriptionFailure("boom"))
        XCTAssertEqual(reason?.appError, .transcriptionFailure("The preserved recording is waiting for transcription retry."))

        let message = PendingTranscriptionFailureReason.transcriptionFailure.retryMessage(for: .openAI)
        XCTAssertTrue(message.contains("Recording saved locally"), message)
        XCTAssertTrue(message.lowercased().contains("retry"), message)
    }

    /// Failures that are not about transcription must NOT be turned into
    /// pending-transcription state — that would fabricate a retryable session
    /// out of, say, a disk error.
    func testNonTranscriptionFailuresStillTakeTheCleanupPath() {
        for error in [AppError.storageFailure("disk full"), .screenshotCaptureFailure("no permission")] {
            XCTAssertNil(
                TranscriptionRecoveryController.preservableStopFailureReason(for: error),
                "\(error) is not a transcription retry state."
            )
        }
    }
}
