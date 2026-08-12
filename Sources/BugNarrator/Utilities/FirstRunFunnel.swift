import Foundation

/// The two first-run decisions that used to be spelled inline in views (#959).
///
/// Kept pure so they can be tested without standing up SwiftUI — the same
/// reason `OnboardingFlow` exists, and the direct response to #918 where a
/// view-only decision no test could reach shipped broken.
enum FirstRunFunnel {
    /// Whether a session may start.
    ///
    /// It used to require a configured AI provider, which walled off the
    /// product's entire first-run path behind a paid API key even though the
    /// record-now/transcribe-later machinery already existed: a stop with no
    /// usable credential preserves the recording as a retryable pending
    /// transcription (`PendingTranscriptionFailureReason.missingAPIKey`).
    ///
    /// So the provider is required to *transcribe*, not to *record*. Blocking
    /// the recording bought nothing and cost every evaluator their first
    /// session.
    static func canStartRecording(phaseAllowsStart: Bool) -> Bool {
        phaseAllowsStart
    }

    /// What the user is promised when they start without a provider, so the
    /// button is honest rather than silently deferring work.
    static func startWithoutProviderNotice(providerName: String) -> String {
        "No \(providerName) setup yet — BugNarrator will record and save the session, and keep it ready to transcribe once you add a provider."
    }

    /// Whether the menu bar should offer the bundled sample session.
    ///
    /// Only with an empty library: once there is real history the offer is
    /// noise. The sample already had a home in the session library's empty
    /// state (#374), but a new user opening the menu bar — the first and often
    /// only surface they see — had no route to it at all.
    static func shouldOfferSampleSession(libraryIsEmpty: Bool) -> Bool {
        libraryIsEmpty
    }
}
