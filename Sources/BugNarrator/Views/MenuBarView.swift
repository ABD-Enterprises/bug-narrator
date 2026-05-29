import AVFoundation
import SwiftUI

struct MenuBarView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var appState: AppState
    @ObservedObject var recordingTimer: RecordingTimerViewModel
    @ObservedObject var transcriptStore: TranscriptStore

    @State private var isOptionKeyPressed = false
    @State private var modifierKeyMonitor: Any?
    @StateObject private var microphoneLevelMonitor = MicrophoneInputLevelMonitor()

    private let metadata = BugNarratorMetadata()

    private var statusPresentation: MenuBarStatusPresentation {
        MenuBarStatusPresentation(status: appState.status, currentError: appState.currentError)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusCard
            if appState.needsAPIKeySetup {
                providerRequirementCard
            }
            controlsSection

            if !transcriptStore.libraryEntries.isEmpty {
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
            syncMicrophoneLevelMonitoring()
        }
        .onDisappear {
            stopModifierKeyMonitoring()
            microphoneLevelMonitor.stop()
        }
        .onChange(of: appState.status.phase) { _, _ in
            syncMicrophoneLevelMonitoring()
        }
        .onChange(of: appState.settingsStore.recordingAudioSource) { _, _ in
            syncMicrophoneLevelMonitoring()
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

                        Text(recordingTimer.elapsedTimeString)
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
        case .systemAudio:
            systemAudioRecoverySection
        case .providerSettings:
            providerSettingsRecoverySection
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

    private var systemAudioRecoverySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appState.currentError?.suggestsSystemAudioSettings == true {
                Text("Open Settings to enable system audio capture modes and acknowledge the recording notice.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Settings") {
                    appState.openSettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Text("System audio capture uses macOS Screen & System Audio Recording permission. Enable BugNarrator there, then try again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Screen & System Audio Settings") {
                    appState.openSystemAudioPrivacySettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Open Screen and System Audio Recording privacy settings")
            }
        }
    }

    private var providerSettingsRecoverySection: some View {
        let provider = appState.settingsStore.aiProvider
        return VStack(alignment: .leading, spacing: 8) {
            Text(provider.requiresAPIKey
                ? "Open Settings to add or replace your \(provider.displayName) API key. BugNarrator stores it in your macOS Keychain when available."
                : "Open Settings to confirm the \(provider.displayName) server and base URL. BugNarrator keeps this local provider setup on this Mac."
            )
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

    private var providerRequirementCard: some View {
        let provider = appState.settingsStore.aiProvider
        return VStack(alignment: .leading, spacing: 10) {
            Label(
                provider.requiresAPIKey ? "Bring Your Own \(provider.displayName) API Key" : "\(provider.displayName) Setup Needed",
                systemImage: provider.requiresAPIKey ? "key.horizontal.fill" : "server.rack"
            )
                .font(.subheadline.weight(.semibold))

            Text(
                provider.requiresAPIKey
                    ? "BugNarrator sends transcription requests to \(provider.displayName). You can start recording without a key, but you need your own API key in Settings before transcription or issue extraction will work. Provider usage may incur charges on your account."
                    : "BugNarrator is configured to use \(provider.displayName) for transcription. Recording can start now, but transcription and issue extraction will not work until the local server and base URL are reachable from this Mac."
            )
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

            microphoneLevelSection

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

    @ViewBuilder
    private var microphoneLevelSection: some View {
        if appState.settingsStore.recordingAudioSource.usesMicrophone {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text("Mic Level")
                        .font(.footnote.weight(.semibold))

                    Spacer()

                    Text(microphoneLevelMonitor.state.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LevelMeterView(level: microphoneLevelMonitor.currentLevel)
                    .frame(height: 8)
                    .accessibilityLabel("Microphone input level")
                    .accessibilityValue(microphoneLevelMonitor.state.accessibilityValue(level: microphoneLevelMonitor.currentLevel))

                if microphoneLevelMonitor.state == .permissionNeeded {
                    Button("Open Microphone Settings") {
                        appState.openMicrophonePrivacySettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 2)
        }
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

    private func syncMicrophoneLevelMonitoring() {
        guard appState.settingsStore.recordingAudioSource.usesMicrophone else {
            microphoneLevelMonitor.stop()
            return
        }

        switch appState.status.phase {
        case .idle, .success, .error:
            microphoneLevelMonitor.start()
        case .recording, .transcribing:
            microphoneLevelMonitor.stop()
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

                    Text(
                        appState.settingsStore.aiProvider.requiresAPIKey
                            ? "Restore or replace the \(appState.settingsStore.aiProvider.displayName) API key in Settings if needed, then reopen the saved session to retry transcription."
                            : "Confirm the \(appState.settingsStore.aiProvider.displayName) setup in Settings if needed, then reopen the saved session to retry transcription."
                    )
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        if appState.needsAPIKeySetup {
                            Button("Open Settings") {
                                appState.openSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Button("Open Retry Needed Session") {
                                openPendingTranscriptionSession()
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
            return currentError.statusTitle(for: appState.settingsStore.aiProvider)
        }

        return appState.status.title
    }
}

struct LevelMeterView: View {
    let level: Float

    private let segmentCount = 18

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(0..<segmentCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(index < activeSegmentCount ? segmentColor(for: index) : Color.secondary.opacity(0.18))
                        .frame(width: segmentWidth(totalWidth: proxy.size.width), height: proxy.size.height)
                }
            }
        }
    }

    private var activeSegmentCount: Int {
        min(segmentCount, max(0, Int(ceil(Double(level) * Double(segmentCount)))))
    }

    private func segmentWidth(totalWidth: CGFloat) -> CGFloat {
        max(2, (totalWidth - CGFloat(segmentCount - 1) * 3) / CGFloat(segmentCount))
    }

    private func segmentColor(for index: Int) -> Color {
        let ratio = Double(index + 1) / Double(segmentCount)
        if ratio > 0.78 {
            return .red
        }
        if ratio > 0.55 {
            return .orange
        }
        return .green
    }
}

@MainActor
final class MicrophoneInputLevelMonitor: ObservableObject {
    @Published private(set) var currentLevel: Float = 0
    @Published private(set) var state: MicrophoneInputLevelState = .idle

    private let engine = AVAudioEngine()
    private var isMonitoring = false

    func start() {
        guard !isMonitoring else {
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startEngine()
        case .notDetermined, .denied, .restricted:
            currentLevel = 0
            state = .permissionNeeded
        @unknown default:
            currentLevel = 0
            state = .unavailable
        }
    }

    func stop() {
        guard isMonitoring || state != .idle || currentLevel != 0 else {
            return
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isMonitoring = false
        currentLevel = 0
        state = .idle
    }

    private func startEngine() {
        do {
            let inputNode = engine.inputNode
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1_024, format: nil) { [weak self] buffer, _ in
                let level = MicrophoneLevelCalculator.normalizedRMSLevel(for: buffer)
                Task { @MainActor [weak self] in
                    self?.currentLevel = level
                }
            }

            try engine.start()
            isMonitoring = true
            state = .monitoring
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            isMonitoring = false
            currentLevel = 0
            state = .unavailable
        }
    }
}

enum MicrophoneInputLevelState: Equatable {
    case idle
    case monitoring
    case permissionNeeded
    case unavailable

    var label: String {
        switch self {
        case .idle:
            return "Paused"
        case .monitoring:
            return "Live"
        case .permissionNeeded:
            return "Permission needed"
        case .unavailable:
            return "Unavailable"
        }
    }

    func accessibilityValue(level: Float) -> String {
        switch self {
        case .monitoring:
            return "\(Int((level * 100).rounded())) percent"
        case .permissionNeeded:
            return "Microphone permission is needed"
        case .unavailable:
            return "Microphone level is unavailable"
        case .idle:
            return "Paused"
        }
    }
}

enum MicrophoneLevelCalculator {
    static func normalizedRMSLevel(for buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else {
            return 0
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else {
            return 0
        }

        var sumOfSquares: Float = 0
        var sampleCount = 0

        for channelIndex in 0..<channelCount {
            let samples = channels[channelIndex]
            for frameIndex in 0..<frameLength {
                let sample = samples[frameIndex]
                sumOfSquares += sample * sample
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else {
            return 0
        }

        let rms = sqrt(sumOfSquares / Float(sampleCount))
        return min(1, max(0, rms * 4))
    }
}
