import AVFoundation
import SwiftUI

/// The first-run welcome tour (#357).
///
/// Every decision this view makes about *what* to show lives in `OnboardingFlow`
/// so it can be unit tested; this file is presentation only. That split is a
/// direct response to #918, where a SwiftUI-only decision no test could reach
/// broke the Settings tabs.
///
/// The tour never configures anything itself. The provider step routes into the
/// existing AI Engines pane rather than duplicating provider UI, and the hotkey
/// step applies suggestions only on an explicit press — nothing here rebinds a
/// shortcut or spends a credential on the user's behalf.
struct WelcomeView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    /// Read from `AVCaptureDevice` rather than plumbed through a service, which
    /// is how `MenuBarView+SetupBanner` already reads it in this layer.
    ///
    /// Held as state and refreshed on re-activation because the user leaves the
    /// app to answer the system prompt, and macOS does not publish the change.
    @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var stepIndex = 0
    @State private var showSkipConfirmation = false

    private let steps = OnboardingStep.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                Group {
                    if OnboardingFlow.isFullyConfigured(snapshot) {
                        allSetPanel
                    } else {
                        stepPanel
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            footer
        }
        .frame(minWidth: 520, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            refreshMicrophoneStatus()
            advanceToFirstIncompleteStep()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshMicrophoneStatus()
        }
        .confirmationDialog(
            skipConfirmationTitle,
            isPresented: $showSkipConfirmation,
            titleVisibility: .visible
        ) {
            Button("Skip Setup", role: .destructive) {
                finish()
            }
            Button("Keep Setting Up", role: .cancel) {}
        } message: {
            Text(skipConfirmationMessage)
        }
    }

    // MARK: - Snapshot

    /// The plain-value view of readiness that every decision below reads from.
    ///
    /// `notDetermined` maps to `false`: during onboarding we are asking, not
    /// reacting to a failure, so "not yet answered" is not "granted".
    var snapshot: OnboardingSnapshot {
        OnboardingSnapshot(
            hasUsableAIProviderCredential: settingsStore.hasUsableAIProviderCredential,
            providerConfigurationIsCompatible: settingsStore.aiProviderCompatibilityIssue == nil,
            microphoneAuthorized: microphoneStatus == .authorized,
            hasAnyCaptureHotkeyAssigned: settingsStore.hasAnyCaptureHotkeyAssigned
        )
    }

    private var currentStep: OnboardingStep {
        steps[min(max(stepIndex, 0), steps.count - 1)]
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Welcome to BugNarrator")
                .font(.largeTitle.weight(.bold))

            Text("Record what you are testing, narrate the problem out loud, and get a written transcript with the issues already pulled out. Three quick things and you are recording.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            stepIndicator
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepIndicator: some View {
        HStack(spacing: 14) {
            ForEach(steps) { step in
                let complete = OnboardingFlow.isComplete(step, in: snapshot)
                Label {
                    Text(step.title)
                        .font(.caption)
                        .foregroundStyle(step == currentStep ? .primary : .secondary)
                } icon: {
                    Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(complete ? Color.green : Color.secondary)
                }
                .accessibilityLabel("\(step.title): \(complete ? "done" : "not done yet")")
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Terminal state

    private var allSetPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("You are all set", systemImage: "checkmark.seal.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.green)

            Text("Your AI provider, microphone access, and capture hotkeys are all configured. Start a session from the menu bar whenever you are ready.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private var stepPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(currentStep.title)
                .font(.title3.weight(.semibold))

            switch currentStep {
            case .provider:
                providerStep
            case .microphone:
                microphoneStep
            case .hotkeys:
                hotkeyStep
            }
        }
    }

    @ViewBuilder
    private var providerStep: some View {
        stepBody(
            detail: "BugNarrator sends your recording to an AI provider to transcribe it and pull out the issues. Pick a provider and paste a key — or choose a local engine that needs no key at all.",
            isComplete: OnboardingFlow.isComplete(.provider, in: snapshot),
            completeMessage: "Provider ready."
        )

        if let compatibilityIssue = settingsStore.aiProviderCompatibilityIssue {
            Label(compatibilityIssue, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        Button("Open AI Engines Settings") {
            appState.openSettings()
        }
        .help("Settings opens on the AI Engines pane while a provider still needs configuring.")

        Text("This is the only step that gates recording. The other two make BugNarrator nicer to use, and you can skip them.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var microphoneStep: some View {
        stepBody(
            detail: "BugNarrator records your narration, so macOS needs to grant it microphone access.",
            isComplete: OnboardingFlow.isComplete(.microphone, in: snapshot),
            completeMessage: "Microphone access granted."
        )

        switch microphoneStatus {
        case .notDetermined:
            Button("Allow Microphone Access") {
                requestMicrophoneAccess()
            }
            .help("Asks macOS for microphone access. You can also grant it later, the first time you record.")
        case .denied, .restricted:
            VStack(alignment: .leading, spacing: 8) {
                Text("macOS is currently blocking microphone access for BugNarrator. Turn it back on in System Settings, then return here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Microphone Settings") {
                    appState.openMicrophonePrivacySettings()
                }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var hotkeyStep: some View {
        stepBody(
            detail: "Global shortcuts let you start, stop, and grab a screenshot without leaving the app you are testing. BugNarrator ships with none bound, so nothing of yours is overwritten.",
            isComplete: OnboardingFlow.isComplete(.hotkeys, in: snapshot),
            completeMessage: "At least one capture hotkey is assigned."
        )

        VStack(alignment: .leading, spacing: 6) {
            ForEach(settingsStore.hotkeyAssignments, id: \.action) { assignment in
                HStack {
                    Text(assignment.action.title)
                        .font(.footnote)
                    Spacer()
                    Text(assignment.shortcut.isEnabled ? assignment.shortcut.displayString : "Not assigned")
                        .font(.footnote.monospaced())
                        .foregroundStyle(assignment.shortcut.isEnabled ? .primary : .secondary)
                }
            }
        }

        if !availableSuggestions.isEmpty {
            Button("Use Suggested Shortcuts") {
                applySuggestedShortcuts()
            }
            .help("Applies the recommended shortcut to every capture action that is still unassigned.")
        }

        Text("Nothing is bound until you press the button, and you can change any of these later in Settings › General.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func stepBody(detail: String, isComplete: Bool, completeMessage: String) -> some View {
        Text(detail)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        if isComplete {
            Label(completeMessage, systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Skip Setup") {
                skip()
            }
            .buttonStyle(.borderless)
            .accessibilityHint("Closes the tour. Anything left unconfigured stays unconfigured.")

            Spacer()

            if !OnboardingFlow.isFullyConfigured(snapshot) {
                Button("Back") {
                    stepIndex = max(stepIndex - 1, 0)
                }
                .disabled(stepIndex == 0)
            }

            Button(primaryButtonTitle) {
                if isOnLastStep || OnboardingFlow.isFullyConfigured(snapshot) {
                    finish()
                } else {
                    stepIndex = min(stepIndex + 1, steps.count - 1)
                }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var isOnLastStep: Bool {
        stepIndex >= steps.count - 1
    }

    private var primaryButtonTitle: String {
        isOnLastStep || OnboardingFlow.isFullyConfigured(snapshot) ? "Done" : "Next"
    }

    // MARK: - Skip copy

    private var skipConfirmationTitle: String {
        "Skip setup?"
    }

    /// Names only the steps that actually block recording, rather than warning
    /// about every incomplete one — skipping the hotkey step costs nothing.
    private var skipConfirmationMessage: String {
        let blocking = OnboardingFlow.blockingIncompleteSteps(in: snapshot)
        guard !blocking.isEmpty else {
            return "You can reopen this tour any time from Help › Show Welcome Tour."
        }

        let names = blocking.map(\.title).joined(separator: ", ")
        return "BugNarrator cannot transcribe a recording until this is done: \(names). You can finish it later in Settings, or reopen this tour from Help › Show Welcome Tour."
    }

    // MARK: - Actions

    /// Opens on the first thing the user actually still needs, so a partially
    /// configured install is not walked through fields it has already filled in.
    private func advanceToFirstIncompleteStep() {
        guard let first = OnboardingFlow.firstIncompleteStep(in: snapshot),
              let index = steps.firstIndex(of: first) else {
            return
        }

        stepIndex = index
    }

    private func refreshMicrophoneStatus() {
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }

    private func requestMicrophoneAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in
                refreshMicrophoneStatus()
            }
        }
    }

    private var availableSuggestions: [(action: HotkeyAction, shortcut: HotkeyShortcut)] {
        settingsStore.hotkeyAssignments.compactMap { assignment in
            guard !assignment.shortcut.isEnabled,
                  let suggestion = settingsStore.suggestedShortcutIfAvailable(for: assignment.action) else {
                return nil
            }

            return (assignment.action, suggestion)
        }
    }

    /// Only fills empty slots. A shortcut the user already chose is never
    /// replaced, and `migrateLegacyBuiltInHotkeysIfNeeded` is untouched — this
    /// is an offer, not a restoration of the 1.0.11 built-in defaults.
    private func applySuggestedShortcuts() {
        for suggestion in availableSuggestions {
            switch suggestion.action {
            case .startRecording:
                settingsStore.startRecordingHotkeyShortcut = suggestion.shortcut
            case .stopRecording:
                settingsStore.stopRecordingHotkeyShortcut = suggestion.shortcut
            case .captureScreenshot:
                settingsStore.screenshotHotkeyShortcut = suggestion.shortcut
            }
        }
    }

    private func skip() {
        if OnboardingFlow.blockingIncompleteSteps(in: snapshot).isEmpty {
            finish()
        } else {
            showSkipConfirmation = true
        }
    }

    /// Skipping and completing are the same thing on purpose: dismissing the
    /// tour has to be durable, or an unconfigured user is re-prompted on every
    /// launch. The launch path already stamps the flag when it presents the
    /// window, which is what makes the close box equivalent too; this call is
    /// what covers the Help-menu reopen. Neither fabricates readiness — the
    /// finish-setup banner (#378) and the recording gate still see real state.
    private func finish() {
        settingsStore.markFirstRunOnboardingCompleted()
        dismiss()
    }
}
