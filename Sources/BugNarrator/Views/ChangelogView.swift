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

                Text(changelog.attributedMarkdown)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
}
