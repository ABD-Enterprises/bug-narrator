import SwiftUI

/// Shared readiness/status model + view components for the Settings surface,
/// extracted from `SettingsView` (#530, an #355 A3 precursor) so both the
/// top-level "at a glance" status summary and the Integrations pane can compute
/// and render the same status rows. Pure relocation: identical logic and layout.

/// The configured-ness of a Settings capability (AI provider, GitHub, Jira).
enum SettingsReadinessStatus {
    case ready
    case needsSetup
    case pendingSave
    case locked

    var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .needsSetup:
            return "Needs setup"
        case .pendingSave:
            return "Pending save"
        case .locked:
            return "Locked"
        }
    }

    var symbolName: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"
        case .needsSetup:
            return "exclamationmark.circle.fill"
        case .pendingSave:
            return "clock.fill"
        case .locked:
            return "lock.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready:
            return .green
        case .needsSetup:
            return .orange
        case .pendingSave:
            return .blue
        case .locked:
            return .red
        }
    }
}

/// One row in a per-integration prerequisite checklist.
struct PrerequisiteRow: Identifiable {
    let title: String
    let detail: String
    let status: SettingsReadinessStatus

    var id: String {
        title
    }
}

/// Pure readiness computations derived from `SettingsStore` state.
enum SettingsReadiness {
    static func credentialStatus(
        valueIsPresent: Bool,
        persistenceState: APIKeyPersistenceState
    ) -> SettingsReadinessStatus {
        switch persistenceState {
        case .pendingSave:
            return .pendingSave
        case .keychainLocked:
            return .locked
        case .empty:
            return .needsSetup
        case .keychain, .sessionOnly:
            return valueIsPresent ? .ready : .needsSetup
        }
    }

    static func prerequisiteStatus(
        for persistenceState: APIKeyPersistenceState,
        isReady: Bool
    ) -> SettingsReadinessStatus {
        switch persistenceState {
        case .pendingSave:
            return .pendingSave
        case .keychainLocked:
            return .locked
        default:
            return isReady ? .ready : .needsSetup
        }
    }

    static func openAIReadiness(_ settingsStore: SettingsStore) -> SettingsReadinessStatus {
        if !settingsStore.aiProvider.requiresAPIKey {
            return settingsStore.aiProviderConfigurationIsReady ? .ready : .needsSetup
        }

        return credentialStatus(
            valueIsPresent: settingsStore.aiProviderConfigurationIsReady,
            persistenceState: settingsStore.apiKeyPersistenceState
        )
    }

    static func gitHubReadiness(_ settingsStore: SettingsStore) -> SettingsReadinessStatus {
        if settingsStore.githubTokenPersistenceState == .pendingSave {
            return .pendingSave
        }

        if settingsStore.githubTokenPersistenceState == .keychainLocked {
            return .locked
        }

        return settingsStore.githubExportConfiguration == nil ? .needsSetup : .ready
    }

    static func jiraReadiness(_ settingsStore: SettingsStore) -> SettingsReadinessStatus {
        if settingsStore.jiraEmailPersistenceState == .pendingSave ||
            settingsStore.jiraTokenPersistenceState == .pendingSave {
            return .pendingSave
        }

        if settingsStore.jiraEmailPersistenceState == .keychainLocked ||
            settingsStore.jiraTokenPersistenceState == .keychainLocked {
            return .locked
        }

        return settingsStore.jiraExportConfiguration == nil ? .needsSetup : .ready
    }
}

/// A "Settings at a glance" status row: icon + title/detail + status capsule.
func settingsStatusRow(
    title: String,
    detail: String,
    status: SettingsReadinessStatus,
    accessibilityLabel: String
) -> some View {
    HStack(spacing: 10) {
        Image(systemName: status.symbolName)
            .foregroundStyle(status.color)
            .frame(width: 18)

        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.medium))

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Spacer(minLength: 12)

        Text(status.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.12), in: Capsule())
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
}

/// A titled checklist of per-integration prerequisite rows.
func settingsPrerequisiteChecklist(title: String, rows: [PrerequisiteRow]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

        VStack(spacing: 6) {
            ForEach(rows) { row in
                settingsPrerequisiteRow(row)
            }
        }
    }
    .padding(10)
    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(.quaternary, lineWidth: 1)
    )
}

/// A single prerequisite row within `settingsPrerequisiteChecklist`.
func settingsPrerequisiteRow(_ row: PrerequisiteRow) -> some View {
    HStack(spacing: 8) {
        Image(systemName: row.status.symbolName)
            .foregroundStyle(row.status.color)
            .frame(width: 16)

        Text(row.title)
            .font(.caption.weight(.medium))

        Text(row.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)

        Spacer()

        Text(row.status.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(row.status.color)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(row.title) prerequisite: \(row.status.title)")
}
