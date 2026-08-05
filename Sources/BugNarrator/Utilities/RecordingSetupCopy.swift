import Foundation

/// Copy shown while AI provider setup is incomplete (#910).
///
/// The menu bar and the empty session library each carried their own version of
/// this text, and both told the user they could start recording without
/// finishing setup. That is not true on either path: recording is gated by
/// `AppState.needsAPIKeySetup`, which is true both when a key-requiring provider
/// has no usable credential *and* when any provider has an
/// `aiProviderCompatibilityIssue`. The record control is disabled and
/// `startSession` rejects the attempt, so the user was invited to do something
/// the app refuses.
///
/// Both surfaces now read from here so they cannot drift apart again.
enum RecordingSetupCopy {
    /// Menu bar setup banner body.
    static func menuBannerDescription(for provider: AIProvider) -> String {
        if provider.requiresAPIKey {
            return "BugNarrator sends transcription requests to \(provider.displayName). Add your own API key in Settings before recording — transcription and issue extraction cannot run without it. Provider usage may incur charges on your account."
        }

        return "BugNarrator is configured to use \(provider.displayName) for transcription. Finish setup before recording — the local server and base URL must be reachable from this Mac."
    }

    /// Empty session library setup body.
    static func emptyLibraryDescription(for provider: AIProvider) -> String {
        if provider.requiresAPIKey {
            return "Add a \(provider.displayName) API key in Settings before recording. Sessions cannot be transcribed into the library without one."
        }

        return "Finish \(provider.displayName) setup before recording. Transcription needs the local server and base URL to be reachable from this Mac."
    }
}
