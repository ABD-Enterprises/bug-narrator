import SwiftUI

struct ChangelogView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var settingsStore: SettingsStore

    private let changelog: ChangelogDocument

    init(appState: AppState, changelog: ChangelogDocument = ChangelogDocument()) {
        self.appState = appState
        self.settingsStore = appState.settingsStore
        self.changelog = changelog
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection

                if changelog.releases.isEmpty {
                    Text(changelog.attributedMarkdown)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(changelog.releases) { release in
                            releaseCard(release)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(changelog.title)
                    .font(.largeTitle.weight(.bold))

                Spacer()

                Button("GitHub Releases") {
                    appState.checkForUpdates()
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Open the BugNarrator releases page")
            }

            Text("Release notes for BugNarrator. Use this as a lightweight in-app view of the bundled changelog.")
                .font(.body)
                .foregroundStyle(.secondary)

            Toggle("Show automatically after each update", isOn: $settingsStore.autoShowChangelogOnUpdate)
                .font(.subheadline)
                .accessibilityLabel("Show the changelog automatically after each update")
        }
    }

    private func releaseCard(_ release: ChangelogRelease) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(release.version)
                    .font(.headline.weight(.semibold))

                if let date = release.date {
                    Text(date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(release.notes.enumerated()), id: \.offset) { _, note in
                    releaseNoteRow(note)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        }
    }

    private func releaseNoteRow(_ note: ChangelogReleaseNote) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let category = note.category {
                Text(category)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(categoryColor(category))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(categoryColor(category).opacity(0.14), in: Capsule())
            }

            Text(note.text)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func categoryColor(_ category: String) -> Color {
        switch category.uppercased() {
        case "FIX":
            return .green
        case "CHANGE":
            return .blue
        case "INTERNAL":
            return .secondary
        default:
            return .accentColor
        }
    }
}
