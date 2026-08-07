import AppKit
import SwiftUI

/// Permission and configuration recovery sections for the menu bar popover
/// (#433 slice: MenuStatusCardView recovery subviews).
///
/// Byte-preserving relocation of the seven recovery sections out of
/// `MenuBarView`. Each one renders the "here is how to fix it" affordance for a
/// specific failed precondition — microphone, screen recording, system audio,
/// AI provider, export configuration, storage — plus the generic status
/// recovery row.
///
/// They only read `appState` and `statusPresentation`, which is why this is the
/// lowest-coupling cut in the file. `private` became `internal` so the
/// extension can see them; Swift scopes `private` per file.
extension MenuBarView {
    var microphoneRecoverySection: some View {
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
    var statusRecoverySection: some View {
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

    var screenRecordingRecoverySection: some View {
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

    var systemAudioRecoverySection: some View {
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

    var providerSettingsRecoverySection: some View {
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

    var exportConfigurationRecoverySection: some View {
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

    var storageRecoverySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The transcript is still available in BugNarrator. Copy it now, then fix local storage and save it to history.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Copy Transcript") {
                    appState.copyDisplayedTranscript()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(appState.currentTranscript?.hasTranscriptContent != true)

                Button("Open Transcript Window") {
                    appState.openTranscriptHistory()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
