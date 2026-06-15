import SwiftUI

/// Product info, help, and support links shown in the menu bar popover.
///
/// Extracted from `MenuBarView` as the first focused section split for #433.
/// Behavior is unchanged: the `isOptionKeyPressed` flag still reveals the
/// debug-bundle export, and every action delegates to `AppState`.
struct MenuProductInfoView: View {
    let appState: AppState
    let isOptionKeyPressed: Bool

    var body: some View {
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
}
