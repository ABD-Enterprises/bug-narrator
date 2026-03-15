import AppKit
import SwiftUI

struct AboutBugNarratorView: View {
    @ObservedObject var appState: AppState

    private let metadata: BugNarratorMetadata
    private let changelog: ChangelogDocument

    init(
        appState: AppState,
        metadata: BugNarratorMetadata = BugNarratorMetadata(),
        changelog: ChangelogDocument = ChangelogDocument()
    ) {
        self.appState = appState
        self.metadata = metadata
        self.changelog = changelog
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                descriptionCard
                actionsCard
                whatsNewCard
                supportCard
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(metadata.appName)
                    .font(.largeTitle.weight(.bold))

                Text(metadata.tagline)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Label(metadata.versionDescription, systemImage: "shippingbox")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary.opacity(0.65), in: Capsule())

                    if let copyrightLine = metadata.copyrightLine {
                        Text(copyrightLine)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Product Overview")
                .font(.headline)

            Text(metadata.productDescription)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("BugNarrator is built around one workflow: record a narrated session, review the evidence, refine the issues, then export only what matters.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Project Links")
                .font(.headline)

            actionRow(
                title: "GitHub Repository",
                subtitle: "Source, releases, roadmap, and issue tracking",
                systemImage: "chevron.left.forwardslash.chevron.right",
                accessibilityLabel: "Open the BugNarrator GitHub repository",
                action: appState.openGitHubRepository
            )

            actionRow(
                title: "Documentation",
                subtitle: "Read install help, workflow guidance, and troubleshooting notes",
                systemImage: "book.closed",
                accessibilityLabel: "Open the BugNarrator documentation",
                action: appState.openDocumentation
            )

            actionRow(
                title: "Report an Issue",
                subtitle: "Open the GitHub new issue form for bugs, regressions, and feature requests",
                systemImage: "ladybug",
                accessibilityLabel: "Open the BugNarrator issue tracker",
                action: appState.openIssueReporter
            )

            actionRow(
                title: "Check for Updates",
                subtitle: "Open the GitHub Releases page for the latest notarized DMG",
                systemImage: "arrow.clockwise.circle",
                accessibilityLabel: "Open the BugNarrator releases page",
                action: appState.checkForUpdates
            )
        }
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var whatsNewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("What’s New")
                    .font(.headline)

                Spacer()

                Button("View Changelog") {
                    appState.openChangelog()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Open the BugNarrator changelog window")
            }

            if changelog.latestHighlights.isEmpty {
                Text("No release notes are bundled yet.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(changelog.latestHighlights, id: \.self) { highlight in
                    Label(highlight, systemImage: "sparkles")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var supportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Support Development")
                .font(.headline)

            Text("BugNarrator is free to use. If it saves you time during review and bug triage, you can optionally support ongoing development through the project’s PayPal page.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Support Development") {
                appState.openSupportDevelopment()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Open the BugNarrator support development options")
        }
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func actionRow(
        title: String,
        subtitle: String,
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "arrow.up.forward")
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
