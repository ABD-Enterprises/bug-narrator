import SwiftUI

/// The review-workspace outer chrome extracted from `TranscriptView` (#629, #401
/// slice b). Owns the 4 layout methods (`reviewWorkspace`, `workspaceHeader`,
/// `workspaceActions`, `workspaceSections`) and the `defaultRetryRecoveryMessage`
/// string constant. TranscriptView keeps its 6 leaf sub-content builders
/// (`extractIssuesButton`, `copyTranscriptButton`, `exportMenu`,
/// `reviewSummarySection`, `extractedIssuesSection`, `screenshotsSection`) and
/// passes them here as `@ViewBuilder` closures — that draws the extraction line
/// at layout vs. leaf-content, without dragging in every issue-editor helper.
///
/// Pixel-preserving: the outer `VStack` + `dividerSection` + rounded background
/// and the two workspaceActions layout branches (narrow < 420pt vs wide) are a
/// verbatim relocation of the pre-#629 code.
struct ReviewWorkspaceShell<
    ExtractIssuesButton: View,
    CopyTranscriptButton: View,
    ExportMenu: View,
    ReviewSummarySectionContent: View,
    ExtractedIssuesSectionContent: View,
    ScreenshotsSectionContent: View
>: View {
    let session: TranscriptSession
    let availableWidth: CGFloat
    @ObservedObject var appState: AppState
    @ObservedObject var recordingTimer: RecordingTimerViewModel
    let defaultRetryRecoveryMessage: String

    let extractIssuesButton: () -> ExtractIssuesButton
    let copyTranscriptButton: () -> CopyTranscriptButton
    let exportMenu: () -> ExportMenu
    let reviewSummarySection: () -> ReviewSummarySectionContent
    let extractedIssuesSection: () -> ExtractedIssuesSectionContent
    let screenshotsSection: () -> ScreenshotsSectionContent

    init(
        session: TranscriptSession,
        availableWidth: CGFloat,
        appState: AppState,
        recordingTimer: RecordingTimerViewModel,
        defaultRetryRecoveryMessage: String,
        @ViewBuilder extractIssuesButton: @escaping () -> ExtractIssuesButton,
        @ViewBuilder copyTranscriptButton: @escaping () -> CopyTranscriptButton,
        @ViewBuilder exportMenu: @escaping () -> ExportMenu,
        @ViewBuilder reviewSummarySection: @escaping () -> ReviewSummarySectionContent,
        @ViewBuilder extractedIssuesSection: @escaping () -> ExtractedIssuesSectionContent,
        @ViewBuilder screenshotsSection: @escaping () -> ScreenshotsSectionContent
    ) {
        self.session = session
        self.availableWidth = availableWidth
        self.appState = appState
        self.recordingTimer = recordingTimer
        self.defaultRetryRecoveryMessage = defaultRetryRecoveryMessage
        self.extractIssuesButton = extractIssuesButton
        self.copyTranscriptButton = copyTranscriptButton
        self.exportMenu = exportMenu
        self.reviewSummarySection = reviewSummarySection
        self.extractedIssuesSection = extractedIssuesSection
        self.screenshotsSection = screenshotsSection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            workspaceHeader
            dividerSection
            workspaceActions
            dividerSection
            workspaceSections
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.title)
                .font(availableWidth < 360 ? .title3.weight(.semibold) : .title2.weight(.semibold))

            Text(sessionMetadataLine)
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if session.requiresTranscriptionRetry {
                HStack(alignment: .center, spacing: 10) {
                    Label(
                        session.transcriptionRetryMessage(for: appState.settingsStore.aiProvider) ?? defaultRetryRecoveryMessage,
                        systemImage: "arrow.clockwise.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Spacer()

                    if appState.needsAPIKeySetup {
                        Button("Open Settings") {
                            appState.openSettings()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button("Retry Transcription") {
                            Task {
                                await appState.retryPendingTranscription(for: session.id)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            } else if appState.isUnsaved(session.id) {
                HStack(spacing: 10) {
                    Label("Only stored in memory until you save it.", systemImage: "tray")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Save to History") {
                        appState.saveCurrentTranscriptToHistory()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if appState.isActiveRecordingSession(session.id) {
                HStack(spacing: 10) {
                    Label("Recording is active", systemImage: "record.circle.fill")
                        .foregroundStyle(.red)

                    Text(recordingTimer.elapsedTimeString)
                        .font(.system(.footnote, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Open Recording Controls") {
                        appState.openRecordingControls()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .font(.footnote)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var workspaceActions: some View {
        Group {
            if availableWidth < 420 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        extractIssuesButton()
                        copyTranscriptButton()
                    }

                    exportMenu()
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    extractIssuesButton()
                    copyTranscriptButton()

                    Spacer(minLength: 12)

                    exportMenu()
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var workspaceSections: some View {
        VStack(alignment: .leading, spacing: 16) {
            reviewSectionCard("Review Summary") {
                reviewSummarySection()
            }

            if !session.transcriptQualityFindings.isEmpty {
                reviewSectionCard("Transcript Quality") {
                    TranscriptQualityFindingsView(findings: session.transcriptQualityFindings)
                }
            }

            reviewSectionCard("Extracted Issues") {
                extractedIssuesSection()
            }

            if session.issueExtraction == nil {
                reviewSectionCard("Screenshots") {
                    screenshotsSection()
                }
            }

            reviewSectionCard("Transcript Timeline") {
                RawTranscriptSection(session: session, availableWidth: availableWidth, appState: appState)
            }
        }
    }

    private var sessionMetadataLine: String {
        "\(session.createdAt.formatted(date: .abbreviated, time: .shortened)) • \(ElapsedTimeFormatter.string(from: session.duration)) • \(session.model)"
    }

    private var dividerSection: some View {
        Divider()
            .overlay(Color(nsColor: .separatorColor).opacity(0.45))
    }

    @ViewBuilder
    private func reviewSectionCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
