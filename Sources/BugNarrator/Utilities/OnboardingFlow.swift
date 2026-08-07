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
    /// Two independent reasons not to: the user has already been through it
    /// (or skipped it), or there is nothing left to tell them. The second case
    /// matters for an existing install upgrading into this feature — it must
    /// not greet a long-time user with a setup tour.
    static func shouldPresentOnLaunch(
        hasCompletedFirstRunOnboarding: Bool,
        snapshot: OnboardingSnapshot
    ) -> Bool {
        guard !hasCompletedFirstRunOnboarding else { return false }
        return !isFullyConfigured(snapshot)
    }

    /// Steps that still block recording if left undone — what a skip warning
    /// should name, rather than warning about every incomplete step.
    static func blockingIncompleteSteps(in snapshot: OnboardingSnapshot) -> [OnboardingStep] {
        OnboardingStep.allCases.filter { $0.blocksRecording && !isComplete($0, in: snapshot) }
    }
}
