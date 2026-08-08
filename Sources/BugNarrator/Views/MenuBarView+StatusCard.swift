import AVFoundation
import CoreGraphics
import SwiftUI

/// The menu bar status card and the provider-requirement card (#433 slice 3).
///
/// Byte-preserving relocation of `statusCard`, `preferredMenuWidth`, and
/// `providerRequirementCard`. The recovery rows these compose were extracted
/// separately in slice 1 (`MenuBarView+RecoverySections.swift`).
extension MenuBarView {
    var statusCard: some View {
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


    var preferredMenuWidth: CGFloat {
        statusPresentation.preferredWidth
    }

    var providerRequirementCard: some View {
        let provider = appState.settingsStore.aiProvider
        return VStack(alignment: .leading, spacing: 10) {
            Label(
                provider.requiresAPIKey ? "Bring Your Own \(provider.displayName) API Key" : "\(provider.displayName) Setup Needed",
                systemImage: provider.requiresAPIKey ? "key.horizontal.fill" : "server.rack"
            )
                .font(.subheadline.weight(.semibold))

            Text(RecordingSetupCopy.menuBannerDescription(for: provider))
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

}
