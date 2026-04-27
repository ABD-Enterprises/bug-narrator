import SwiftUI

struct MenuBarView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var appState: AppState
    @ObservedObject var transcriptStore: TranscriptStore

    @State private var isOptionKeyPressed = false
    @State private var modifierKeyMonitor: Any?

    private let metadata = BugNarratorMetadata()

    private var statusPresentation: MenuBarStatusPresentation {
        MenuBarStatusPresentation(status: appState.status, currentError: appState.currentError)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusCard
            if appState.needsAPIKeySetup {
                apiKeyRequirementCard
            }
            controlsSection

            if !transcriptStore.sessions.isEmpty {
                sessionLibraryCard
            }

            productInfoSection
            footerSection
        }
        .padding(16)
        .frame(width: preferredMenuWidth)
        .onAppear {
            refreshModifierKeys()
            startModifierKeyMonitoring()
        }
        .onDisappear {
            stopModifierKeyMonitoring()
        }
        .alert("Discard this recording?", isPresented: $appState.showDiscardConfirmation) {
            Button("Discard", role: .destructive) {
                Task {
                    await appState.cancelSession()
                }
            }

            Button("Keep Recording", role: .cancel) {
                appState.showDiscardConfirmation = false
            }
        } message: {
            Text("The current audio file will be deleted and the session will not be transcribed.")
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("BugNarrator")
                        .font(.headline)

                    Text("Session status")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(statusBadgeTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusTint)
            }

            if appState.status.phase == .recording {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)

                        Text("Recording in progress")
                            .font(.subheadline.weight(.medium))

                        Spacer()

                        Text(appState.elapsedTimeString)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                    }

                    if let detail = appState.status.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(appState.currentError == nil ? .secondary : .primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    statusRecoverySection
                }
            } else if appState.status.phase == .transcribing {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(appState.status.detail ?? "Uploading audio and waiting for transcription...")
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    statusRecoverySection
                }
            } else if let detail = appState.status.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(statusTint)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                statusRecoverySection
            } else {
                Text("Ready to start a feedback session.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var microphoneRecoverySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appState.microphoneRecoveryGuidance)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let localTestingNote = appState.microphoneRecoveryLocalTestingNote {
                Text(localTestingNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if appState.currentError?.suggestsMicrophoneSettings == true {
                Button("Open Microphone Settings") {
                    appState.openMicrophonePrivacySettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Open Microphone privacy settings")
                .accessibilityHint("Opens the macOS privacy settings for microphone access")
            }
        }
    }

    @ViewBuilder
    private var statusRecoverySection: some View {
        switch statusPresentation.recoveryAction {
        case .microphone:
            microphoneRecoverySection
        case .screenRecording:
            screenRecordingRecoverySection
        case .openAI:
            openAIKeyRecoverySection
        case .exportConfiguration:
            exportConfigurationRecoverySection
        case .storage:
            storageRecoverySection
        case .none:
            EmptyView()
        }
    }

    private var screenRecordingRecoverySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recording can continue without screenshots. To capture them again, enable BugNarrator in Privacy & Security > Screen & System Audio Recording.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Screen Recording Settings") {
                appState.openScreenRecordingPrivacySettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityLabel("Open Screen Recording privacy settings")
            .accessibilityHint("Opens the macOS privacy settings for screen recording access")
        }
    }

    private var openAIKeyRecoverySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Open Settings to add or replace your own OpenAI API key. BugNarrator stores it in your macOS Keychain when available.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Settings") {
                appState.openSettings()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var exportConfigurationRecoverySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Open Settings and finish the GitHub or Jira export configuration before exporting issues.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Settings") {
                appState.openSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var storageRecoverySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The transcript is still available in BugNarrator. After fixing local storage, open the transcript window and save it to history.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Transcript Window") {
                appState.openTranscriptHistory()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var preferredMenuWidth: CGFloat {
        statusPresentation.preferredWidth
    }

    private var apiKeyRequirementCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Bring Your Own OpenAI API Key", systemImage: "key.horizontal.fill")
                .font(.subheadline.weight(.semibold))

            Text("BugNarrator sends transcription requests to the OpenAI API. You can start recording without a key, but you need your own API key in Settings before transcription or issue extraction will work. OpenAI usage may incur charges on your account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Open Settings") {
                appState.openSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recording Controls")
                    .font(.headline)

                Text(sessionControlsSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("Show Recording Controls") {
                runMenuAction {
                    appState.openRecordingControls()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint("Opens the recording controls window.")

            switch appState.status.phase {
            case .idle:
                Text("Open the control window to start, stop, and capture screenshots that automatically mark important moments. Global shortcuts stay active too.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .recording:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recording is active. Keep the control window parked where you want it while you keep testing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("\(appState.activeTimelineMomentCount) timeline moments  •  \(appState.activeScreenshotCount) screenshots")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .transcribing:
                Text("The control window can stay open while BugNarrator uploads audio and prepares the transcript.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .success:
                Text("The latest session is ready in the session library. Reopen the control window when you want to start the next pass.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .error:
                Text("Use the recovery guidance above, then continue from the control window.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !assignedHotkeyLines.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Global Hotkeys")
                        .font(.footnote.weight(.semibold))

                    ForEach(assignedHotkeyLines, id: \.label) { line in
                        hotkeyLine(label: line.label, value: line.value)
                    }
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var assignedHotkeyLines: [(label: String, value: String)] {
        [
            ("Start", appState.settingsStore.startRecordingHotkeyShortcut.displayStringIfEnabled),
            ("Stop", appState.settingsStore.stopRecordingHotkeyShortcut.displayStringIfEnabled),
            ("Screenshot", appState.settingsStore.screenshotHotkeyShortcut.displayStringIfEnabled)
        ]
        .compactMap { label, value in
            guard let value else {
                return nil
            }

            return (label: label, value: value)
        }
    }

    private var sessionLibraryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Open Session Library") {
                appState.openTranscriptHistory()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHint("Opens the session library window.")

            if transcriptStore.pendingTranscriptionSessionCount > 0 {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(pendingTranscriptionSummary)
                        .font(.footnote.weight(.semibold))

                    Text("Restore or replace the OpenAI API key in Settings if needed, then reopen the saved session to retry transcription.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        if appState.settingsStore.hasAPIKey {
                            Button("Open Retry Needed Session") {
                                openPendingTranscriptionSession()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Button("Open Settings") {
                                appState.openSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Button("View Library") {
                            appState.openTranscriptHistory()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var footerSection: some View {
        HStack(spacing: 10) {
            Button("Settings") {
                appState.openSettings()
            }

            Spacer()

            Text(metadata.versionDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Quit") {
                appState.requestApplicationTermination()
            }
        }
    }

    private func runMenuAction(
        delayNanoseconds: UInt64 = 250_000_000,
        action: @escaping @MainActor () async -> Void
    ) {
        dismiss()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            await action()
        }
    }

    private var productInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Product Info")
                .font(.headline)

            Text("Documentation, diagnostics, support, and release notes.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            infoButton(
                title: "About BugNarrator",
                systemImage: "info.circle",
                accessibilityLabel: "Open the BugNarrator about window",
                action: appState.openAbout
            )

            infoButton(
                title: "What’s New",
                systemImage: "sparkles.rectangle.stack",
                accessibilityLabel: "Open the BugNarrator changelog",
                action: appState.openChangelog
            )

            Divider()

            Text("Help And Support")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            infoButton(
                title: "View Documentation",
                systemImage: "book.closed",
                accessibilityLabel: "Open the BugNarrator documentation",
                action: appState.openDocumentation
            )

            infoButton(
                title: "Report an Issue",
                systemImage: "ladybug",
                accessibilityLabel: "Open the BugNarrator issue tracker",
                action: appState.openIssueReporter
            )

            if isOptionKeyPressed {
                infoButton(
                    title: "Export Debug Bundle",
                    systemImage: "archivebox",
                    accessibilityLabel: "Export a BugNarrator debug bundle",
                    action: {
                        Task {
                            await appState.exportDebugBundle()
                        }
                    }
                )
            }

            infoButton(
                title: "Support Development",
                systemImage: "heart",
                accessibilityLabel: "Open the BugNarrator support development window",
                action: appState.openSupportDevelopment
            )

            infoButton(
                title: "Check for Updates",
                systemImage: "arrow.clockwise",
                accessibilityLabel: "Open the BugNarrator releases page",
                action: appState.checkForUpdates
            )
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func infoButton(
        title: String,
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.forward")
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func refreshModifierKeys() {
        isOptionKeyPressed = NSEvent.modifierFlags.contains(.option)
    }

    private func startModifierKeyMonitoring() {
        guard modifierKeyMonitor == nil else {
            return
        }

        modifierKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            isOptionKeyPressed = event.modifierFlags.contains(.option)
            return event
        }
    }

    private func stopModifierKeyMonitoring() {
        guard let modifierKeyMonitor else {
            return
        }

        NSEvent.removeMonitor(modifierKeyMonitor)
        self.modifierKeyMonitor = nil
    }

    private var sessionControlsSubtitle: String {
        switch appState.status.phase {
        case .idle:
            return "The control window is the single place for recording actions."
        case .recording:
            return "Keep the controls open and use them or the hotkeys without reopening the menu."
        case .transcribing:
            return "Recording has stopped. The control window stays available while transcription finishes."
        case .success:
            return "Use the control window to start the next session when you are ready."
        case .error:
            return "Fix the current issue, then continue from the control window."
        }
    }

    private var pendingTranscriptionSummary: String {
        let count = transcriptStore.pendingTranscriptionSessionCount
        return count == 1
            ? "1 saved session is waiting for transcription retry."
            : "\(count) saved sessions are waiting for transcription retry."
    }

    private func openPendingTranscriptionSession() {
        if let sessionID = transcriptStore.latestPendingTranscriptionSession?.id {
            appState.selectedTranscriptID = sessionID
        }

        appState.openTranscriptHistory()
    }

    private func hotkeyLine(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .font(.footnote)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) hotkey")
        .accessibilityValue(value)
    }

    private var statusTint: Color {
        switch appState.status.phase {
        case .idle:
            return .secondary
        case .recording:
            return .red
        case .transcribing:
            return .orange
        case .success:
            return .green
        case .error:
            return .red
        }
    }

    private var statusBadgeTitle: String {
        if appState.status.phase == .error, let currentError = appState.currentError {
            return currentError.statusTitle
        }

        return appState.status.title
    }
}
