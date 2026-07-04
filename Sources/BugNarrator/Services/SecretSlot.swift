import Foundation

/// Addresses a single Keychain-backed secret managed by `SettingsStore`
/// (#429 credential slice 3a).
///
/// This is a pure descriptor: it maps each secret to its canonical Keychain
/// `service`/`account`, the legacy `service` names an older build wrote (kept
/// for one-time read-and-migrate), and a redaction-safe label used in logs. It
/// holds no state and performs no Keychain access — `SettingsStore` still owns
/// the persistence, migration, and observable persistence-state machinery.
///
/// The strings here are the storage contract: changing any of them without a
/// migration would orphan an existing secret (Keychain data loss), so they are
/// frozen by `SecretSlotTests`.
enum SecretSlot: Hashable, CaseIterable {
    case openAI
    case github
    case jiraEmail
    case jira

    var service: String {
        switch self {
        case .openAI:
            return "BugNarrator.OpenAI"
        case .github:
            return "BugNarrator.GitHub"
        case .jiraEmail:
            return "BugNarrator.Jira"
        case .jira:
            return "BugNarrator.Jira"
        }
    }

    var legacyServices: [String] {
        switch self {
        case .openAI:
            return ["SessionMic.OpenAI"]
        case .github:
            return ["SessionMic.GitHub"]
        case .jiraEmail:
            return ["SessionMic.Jira"]
        case .jira:
            return ["SessionMic.Jira"]
        }
    }

    var account: String {
        switch self {
        case .openAI:
            return "openai-api-key"
        case .github:
            return "github-token"
        case .jiraEmail:
            return "jira-email"
        case .jira:
            return "jira-api-token"
        }
    }

    var redactionSafeName: String {
        switch self {
        case .openAI:
            return "openai"
        case .github:
            return "github"
        case .jiraEmail:
            return "jira-email"
        case .jira:
            return "jira"
        }
    }
}
