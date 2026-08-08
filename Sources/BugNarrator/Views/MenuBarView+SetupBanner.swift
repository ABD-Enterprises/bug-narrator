import AVFoundation
import CoreGraphics
import SwiftUI

/// The menu bar setup banner and the permission checks that decide whether it
/// appears (#433 slice: MenuSetupBannerView).
///
/// Byte-preserving relocation of the banner cluster out of `MenuBarView`:
/// whether setup is required, whether the banner has been dismissed, the
/// microphone and screen-recording permission probes, the banner itself, and
/// its detail copy.
///
/// `private` became `internal` on the moved members and on
/// `hasDismissedSetupBanner`, because Swift scopes `private` per file. No other
/// visibility changed and no view state moved.
extension MenuBarView {
    var setupBannerRequired: Bool {
        appState.needsAPIKeySetup || microphoneSetupIncomplete
    }

    var shouldShowSetupBanner: Bool {
        setupBannerRequired && !hasDismissedSetupBanner && appState.status.phase != .recording
    }

    var microphoneSetupIncomplete: Bool {
        guard appState.settingsStore.recordingAudioSource.usesMicrophone else {
            return false
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            return true
        case .authorized, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    var screenRecordingSetupIncomplete: Bool {
        !CGPreflightScreenCaptureAccess()
    }

    var setupBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Finish setup to start recording")
                    .font(.subheadline.weight(.semibold))

                Text(setupBannerDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    if appState.needsAPIKeySetup {
                        Button("Open Settings") {
                            appState.openSettings()
                        }
                        .controlSize(.small)
                    }

                    if microphoneSetupIncomplete {
                        Button("Open Microphone Settings") {
                            appState.openMicrophonePrivacySettings()
                        }
                        .controlSize(.small)
                    }
                }
            }

            Spacer()

            Button {
                hasDismissedSetupBanner = true
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss setup banner")
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    var setupBannerDetail: String {
        if appState.needsAPIKeySetup && microphoneSetupIncomplete {
            return "BugNarrator needs microphone access and a configured AI provider before it can record and transcribe."
        }

        if microphoneSetupIncomplete {
            return "BugNarrator needs microphone access before it can record."
        }

        return "Configure your AI provider so recordings can be transcribed."
    }

}
