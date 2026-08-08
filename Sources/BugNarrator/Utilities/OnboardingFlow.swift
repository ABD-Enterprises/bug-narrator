import Foundation

/// The steps a first-run user is walked through (#357).
///
/// Order is the order they are presented in, and it is deliberate: the provider
/// step comes first because it is the only one that actually gates recording
/// (`AppState.needsAPIKeySetup`). Microphone and hotkeys improve the experience
/// but never block it.
enum OnboardingStep: String, CaseIterable, Identifiable, Sendable {
    case provider
    case microphone
    case hotkeys

    var id: String { rawValue }

    var title: String {
        switch self {
        case .provider: return "Choose an AI provider"
        case .microphone: return "Allow microphone access"
        case .hotkeys: return "Set capture hotkeys"
        }
    }

    /// Whether skipping this step leaves the user unable to record.
    ///
    /// Only the provider step does. This is what keeps the flow honest about
    /// which steps are genuinely required versus merely recommended.
    var blocksRecording: Bool {
        self == .provider
    }
}

/// A snapshot of everything the flow needs, as plain values.
///
/// Deliberately not a reference to `SettingsStore`/`AppState`: keeping the
/// inputs primitive is what makes the gating logic testable without standing up
/// an app, and it forces the caller to be explicit about how it maps ambiguous
/// system state (notably `AVAuthorizationStatus.notDetermined`).
struct OnboardingSnapshot: Equatable, Sendable {
    /// Mirrors `SettingsStore.hasUsableAIProviderCredential`.
    let hasUsableAIProviderCredential: Bool
    /// Mirrors `SettingsStore.aiProviderCompatibilityIssue == nil`.
    let providerConfigurationIsCompatible: Bool
    /// True only for an explicit grant. `notDetermined` should map to `false`
    /// here — during onboarding we are asking, not reacting to a failure.
    let microphoneAuthorized: Bool
    /// True when at least one capture hotkey is assigned.
    let hasAnyCaptureHotkeyAssigned: Bool

    init(
        hasUsableAIProviderCredential: Bool,
        providerConfigurationIsCompatible: Bool,
        microphoneAuthorized: Bool,
        hasAnyCaptureHotkeyAssigned: Bool
    ) {
        self.hasUsableAIProviderCredential = hasUsableAIProviderCredential
        self.providerConfigurationIsCompatible = providerConfigurationIsCompatible
        self.microphoneAuthorized = microphoneAuthorized
        self.hasAnyCaptureHotkeyAssigned = hasAnyCaptureHotkeyAssigned
    }
}

/// What a launch is allowed to open unprompted — at most one thing (#357).
enum LaunchPresentation: Equatable, Sendable {
    case welcome
    case changelog
    case none
}

/// Pure step-gating for the first-run flow (#357).
///
/// Every decision the welcome sheet makes lives here so it can be tested
/// without SwiftUI. A previous change on this surface (#918) shipped a
/// SwiftUI-only decision that unit tests could not reach and that broke the
/// Settings tabs; keeping the logic pure is the direct response to that.
enum OnboardingFlow {
    /// Whether a given step is already satisfied.
    static func isComplete(_ step: OnboardingStep, in snapshot: OnboardingSnapshot) -> Bool {
        switch step {
        case .provider:
            // Both halves matter: a credential that fails compatibility (for
            // example whisper-1 selected on a local provider) is not a usable
            // setup even though the credential check passes.
            return snapshot.hasUsableAIProviderCredential && snapshot.providerConfigurationIsCompatible
        case .microphone:
            return snapshot.microphoneAuthorized
        case .hotkeys:
            return snapshot.hasAnyCaptureHotkeyAssigned
        }
    }

    /// The first step still needing attention, or `nil` when everything is set.
    static func firstIncompleteStep(in snapshot: OnboardingSnapshot) -> OnboardingStep? {
        OnboardingStep.allCases.first { !isComplete($0, in: snapshot) }
    }

    /// Every step satisfied — the "you're all set" terminal state, so a
    /// returning user who reopens the tour is not walked through fields they
    /// have already filled in.
    static func isFullyConfigured(_ snapshot: OnboardingSnapshot) -> Bool {
        firstIncompleteStep(in: snapshot) == nil
    }

    /// Whether to present the flow unprompted on launch.
    ///
    /// Three independent reasons not to: the user has already been through it
    /// (or skipped it), there is nothing left to tell them, or they already
    /// have recorded sessions.
    ///
    /// That last gate is load-bearing, not belt-and-braces. Capture hotkeys
    /// ship unbound by the 1.0.11 decision — `migrateLegacyBuiltInHotkeysIfNeeded`
    /// strips the old built-ins — so `isFullyConfigured` is false for very
    /// nearly every existing install. Without `hasExistingUserState`, upgrading
    /// into this feature would greet every long-time user with a setup tour,
    /// which is exactly what this ticket forbids.
    ///
    /// It also keeps this flow and the What's New sheet (#386) mutually
    /// exclusive by construction: the changelog auto-shows only when there *is*
    /// existing user state, and this one only when there is not, so a launch can
    /// never open both windows at once.
    static func shouldPresentOnLaunch(
        hasCompletedFirstRunOnboarding: Bool,
        hasExistingUserState: Bool,
        snapshot: OnboardingSnapshot
    ) -> Bool {
        guard !hasCompletedFirstRunOnboarding else { return false }
        guard !hasExistingUserState else { return false }
        return !isFullyConfigured(snapshot)
    }

    /// The single window a launch may open unprompted.
    ///
    /// Originally the tour and the What's New sheet (#386) were argued to be
    /// mutually exclusive because their gates are opposites. A review of #357
    /// broke that reasoning: a pre-#357 user who saw the changelog (so a version
    /// is recorded), then deleted all local data (so there is no user state),
    /// then upgraded, satisfies both gates and gets two windows. Rather than
    /// patch that path, the precedence is made explicit here — the tour wins,
    /// because someone who still needs setup does not need release notes.
    static func launchPresentation(
        shouldPresentWelcome: Bool,
        shouldAutoShowChangelog: Bool
    ) -> LaunchPresentation {
        if shouldPresentWelcome {
            return .welcome
        }

        return shouldAutoShowChangelog ? .changelog : .none
    }

    /// Steps that still block recording if left undone — what a skip warning
    /// should name, rather than warning about every incomplete step.
    static func blockingIncompleteSteps(in snapshot: OnboardingSnapshot) -> [OnboardingStep] {
        OnboardingStep.allCases.filter { $0.blocksRecording && !isComplete($0, in: snapshot) }
    }
}
