import Combine
import Foundation

final class SettingsStore: ObservableObject {
    @Published var apiKey: String = "" {
        didSet {
            guard hasLoaded else { return }
            apiKeyPersistenceState = persistSecret(apiKey, for: .openAI)
        }
    }

    @Published var preferredModel: String = "whisper-1" {
        didSet {
            guard hasLoaded else { return }
            defaults.set(preferredModel, forKey: Keys.preferredModel)
        }
    }

    @Published var languageHint: String = "" {
        didSet {
            guard hasLoaded else { return }
            defaults.set(languageHint, forKey: Keys.languageHint)
        }
    }

    @Published var transcriptionPrompt: String = "" {
        didSet {
            guard hasLoaded else { return }
            defaults.set(transcriptionPrompt, forKey: Keys.transcriptionPrompt)
        }
    }

    @Published var issueExtractionModel: String = "gpt-4.1-mini" {
        didSet {
            guard hasLoaded else { return }
            defaults.set(issueExtractionModel, forKey: Keys.issueExtractionModel)
        }
    }

    @Published var autoCopyTranscript: Bool = true {
        didSet {
            guard hasLoaded else { return }
            defaults.set(autoCopyTranscript, forKey: Keys.autoCopyTranscript)
        }
    }

    @Published var autoSaveTranscript: Bool = true {
        didSet {
            guard hasLoaded else { return }
            defaults.set(autoSaveTranscript, forKey: Keys.autoSaveTranscript)
        }
    }

    @Published var autoExtractIssues: Bool = false {
        didSet {
            guard hasLoaded else { return }
            defaults.set(autoExtractIssues, forKey: Keys.autoExtractIssues)
        }
    }

    @Published var recordingHotkeyShortcut: HotkeyShortcut = HotkeyAction.toggleRecording.defaultShortcut {
        didSet {
            guard hasLoaded else { return }
            persistHotkey(recordingHotkeyShortcut, key: Keys.recordingHotkeyShortcut)
        }
    }

    @Published var markerHotkeyShortcut: HotkeyShortcut = HotkeyAction.insertMarker.defaultShortcut {
        didSet {
            guard hasLoaded else { return }
            persistHotkey(markerHotkeyShortcut, key: Keys.markerHotkeyShortcut)
        }
    }

    @Published var screenshotHotkeyShortcut: HotkeyShortcut = HotkeyAction.captureScreenshot.defaultShortcut {
        didSet {
            guard hasLoaded else { return }
            persistHotkey(screenshotHotkeyShortcut, key: Keys.screenshotHotkeyShortcut)
        }
    }

    @Published var githubToken: String = "" {
        didSet {
            guard hasLoaded else { return }
            githubTokenPersistenceState = persistSecret(githubToken, for: .github)
        }
    }

    @Published var githubRepositoryOwner: String = "" {
        didSet {
            guard hasLoaded else { return }
            defaults.set(githubRepositoryOwner, forKey: Keys.githubRepositoryOwner)
        }
    }

    @Published var githubRepositoryName: String = "" {
        didSet {
            guard hasLoaded else { return }
            defaults.set(githubRepositoryName, forKey: Keys.githubRepositoryName)
        }
    }

    @Published var githubDefaultLabels: String = "" {
        didSet {
            guard hasLoaded else { return }
            defaults.set(githubDefaultLabels, forKey: Keys.githubDefaultLabels)
        }
    }

    @Published var jiraBaseURL: String = "" {
        didSet {
            guard hasLoaded else { return }
            defaults.set(jiraBaseURL, forKey: Keys.jiraBaseURL)
        }
    }

    @Published var jiraEmail: String = "" {
        didSet {
            guard hasLoaded else { return }
            defaults.set(jiraEmail, forKey: Keys.jiraEmail)
        }
    }

    @Published var jiraAPIToken: String = "" {
        didSet {
            guard hasLoaded else { return }
            jiraTokenPersistenceState = persistSecret(jiraAPIToken, for: .jira)
        }
    }

    @Published var jiraProjectKey: String = "" {
        didSet {
            guard hasLoaded else { return }
            defaults.set(jiraProjectKey, forKey: Keys.jiraProjectKey)
        }
    }

    @Published var jiraIssueType: String = "Task" {
        didSet {
            guard hasLoaded else { return }
            defaults.set(jiraIssueType, forKey: Keys.jiraIssueType)
        }
    }

    @Published var debugMode: Bool = false {
        didSet {
            guard hasLoaded else { return }
            defaults.set(debugMode, forKey: Keys.debugMode)
        }
    }

    @Published private(set) var apiKeyPersistenceState: APIKeyPersistenceState = .empty
    @Published private(set) var githubTokenPersistenceState: APIKeyPersistenceState = .empty
    @Published private(set) var jiraTokenPersistenceState: APIKeyPersistenceState = .empty

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var maskedAPIKey: String {
        mask(secret: trimmedAPIKey, emptyPlaceholder: "No key saved")
    }

    var apiKeyStorageDescription: String {
        storageDescription(
            for: apiKeyPersistenceState,
            empty: "BugNarrator never ships with an OpenAI API key. Paste your own key to enable transcription."
        )
    }

    var preferredModelValue: String {
        let value = preferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "whisper-1" : value
    }

    var normalizedLanguageHint: String? {
        normalizeOptional(languageHint)
    }

    var normalizedPrompt: String? {
        normalizeOptional(transcriptionPrompt)
    }

    var issueExtractionModelValue: String {
        let value = issueExtractionModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "gpt-4.1-mini" : value
    }

    var hasAPIKey: Bool {
        !trimmedAPIKey.isEmpty
    }

    var trimmedGitHubToken: String {
        githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasGitHubToken: Bool {
        !trimmedGitHubToken.isEmpty
    }

    var maskedGitHubToken: String {
        mask(secret: trimmedGitHubToken, emptyPlaceholder: "No token saved")
    }

    var githubTokenStorageDescription: String {
        storageDescription(
            for: githubTokenPersistenceState,
            empty: "Add a GitHub personal access token if you want to export extracted issues to GitHub Issues."
        )
    }

    var normalizedGitHubRepositoryOwner: String {
        githubRepositoryOwner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedGitHubRepositoryName: String {
        githubRepositoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var githubDefaultLabelsList: [String] {
        githubDefaultLabels
            .split(whereSeparator: \.isNewline)
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var githubExportConfiguration: GitHubExportConfiguration? {
        let configuration = GitHubExportConfiguration(
            token: trimmedGitHubToken,
            owner: normalizedGitHubRepositoryOwner,
            repository: normalizedGitHubRepositoryName,
            labels: githubDefaultLabelsList
        )

        return configuration.isComplete ? configuration : nil
    }

    var trimmedJiraAPIToken: String {
        jiraAPIToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasJiraAPIToken: Bool {
        !trimmedJiraAPIToken.isEmpty
    }

    var maskedJiraAPIToken: String {
        mask(secret: trimmedJiraAPIToken, emptyPlaceholder: "No token saved")
    }

    var jiraTokenStorageDescription: String {
        storageDescription(
            for: jiraTokenPersistenceState,
            empty: "Add Jira Cloud credentials if you want to export extracted issues to Jira."
        )
    }

    var normalizedJiraBaseURL: String {
        jiraBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var normalizedJiraEmail: String {
        jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedJiraProjectKey: String {
        jiraProjectKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    var normalizedJiraIssueType: String {
        jiraIssueType.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var jiraExportConfiguration: JiraExportConfiguration? {
        let baseURLString = normalizedJiraBaseURL
        guard !baseURLString.isEmpty,
              let url = URL(string: "https://\(baseURLString)") ?? URL(string: baseURLString) else {
            return nil
        }

        let configuration = JiraExportConfiguration(
            baseURL: url,
            email: normalizedJiraEmail,
            apiToken: trimmedJiraAPIToken,
            projectKey: normalizedJiraProjectKey,
            issueType: normalizedJiraIssueType
        )

        return configuration.isComplete ? configuration : nil
    }

    private let defaults: UserDefaults
    private let keychainService: KeychainServicing
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let legacyDefaultsDomains: [String]
    private var hasLoaded = false
    private var sessionOnlySecrets: [SecretSlot: String] = [:]

    init(
        defaults: UserDefaults = .standard,
        keychainService: KeychainServicing = KeychainService(),
        legacyDefaultsDomains: [String]? = nil
    ) {
        self.defaults = defaults
        self.keychainService = keychainService
        if let legacyDefaultsDomains {
            self.legacyDefaultsDomains = legacyDefaultsDomains
        } else if defaults === UserDefaults.standard {
            self.legacyDefaultsDomains = [
                "com.abdenterprises.sessionmic",
                "com.feedbackmic",
                "com.deffenda.feedbackmic"
            ]
        } else {
            self.legacyDefaultsDomains = []
        }

        load()
        hasLoaded = true
    }

    func refreshSecretsForUserInitiatedAccess() {
        reloadSecrets(slots: Array(SecretSlot.allCases), allowInteraction: true, includeLegacyServices: true)
    }

    func refreshOpenAISecretForUserInitiatedAccess() {
        reloadSecrets(slots: [.openAI], allowInteraction: true, includeLegacyServices: true)
    }

    func refreshExportSecretsForUserInitiatedAccess() {
        reloadSecrets(slots: [.github, .jira], allowInteraction: true, includeLegacyServices: true)
    }

    func removeAPIKey() {
        apiKey = ""
    }

    func removeGitHubToken() {
        githubToken = ""
    }

    func removeJiraAPIToken() {
        jiraAPIToken = ""
    }

    private func load() {
        reloadSecrets(
            slots: Array(SecretSlot.allCases),
            allowInteraction: false,
            includeLegacyServices: true
        )

        preferredModel = stringValue(forKey: Keys.preferredModel) ?? "whisper-1"
        languageHint = stringValue(forKey: Keys.languageHint) ?? ""
        transcriptionPrompt = stringValue(forKey: Keys.transcriptionPrompt) ?? ""
        issueExtractionModel = stringValue(
            forKey: Keys.issueExtractionModel,
            legacyKeys: [Keys.legacyIssueExtractionModel]
        )
            ?? "gpt-4.1-mini"

        autoCopyTranscript = boolValue(forKey: Keys.autoCopyTranscript) ?? true
        autoSaveTranscript = boolValue(forKey: Keys.autoSaveTranscript) ?? true
        autoExtractIssues = boolValue(forKey: Keys.autoExtractIssues) ?? false

        recordingHotkeyShortcut = loadHotkey(
            key: Keys.recordingHotkeyShortcut,
            legacyKey: Keys.legacyRecordingHotkeyShortcut,
            fallback: HotkeyAction.toggleRecording.defaultShortcut
        )
        markerHotkeyShortcut = loadHotkey(
            key: Keys.markerHotkeyShortcut,
            legacyKey: nil,
            fallback: HotkeyAction.insertMarker.defaultShortcut
        )
        screenshotHotkeyShortcut = loadHotkey(
            key: Keys.screenshotHotkeyShortcut,
            legacyKey: nil,
            fallback: HotkeyAction.captureScreenshot.defaultShortcut
        )

        githubRepositoryOwner = stringValue(forKey: Keys.githubRepositoryOwner) ?? ""
        githubRepositoryName = stringValue(forKey: Keys.githubRepositoryName) ?? ""
        githubDefaultLabels = stringValue(forKey: Keys.githubDefaultLabels) ?? ""

        jiraBaseURL = stringValue(forKey: Keys.jiraBaseURL) ?? ""
        jiraEmail = stringValue(forKey: Keys.jiraEmail) ?? ""
        jiraProjectKey = stringValue(forKey: Keys.jiraProjectKey) ?? ""
        jiraIssueType = stringValue(forKey: Keys.jiraIssueType) ?? "Task"

        debugMode = boolValue(forKey: Keys.debugMode) ?? false
    }

    private func reloadSecrets(
        slots: [SecretSlot],
        allowInteraction: Bool,
        includeLegacyServices: Bool
    ) {
        let previousHasLoaded = hasLoaded
        hasLoaded = false
        defer { hasLoaded = previousHasLoaded }

        for slot in slots {
            let secret = loadSecret(
                for: slot,
                allowInteraction: allowInteraction,
                includeLegacyServices: includeLegacyServices
            )

            switch slot {
            case .openAI:
                apiKey = secret.value
                apiKeyPersistenceState = secret.state
            case .github:
                githubToken = secret.value
                githubTokenPersistenceState = secret.state
            case .jira:
                jiraAPIToken = secret.value
                jiraTokenPersistenceState = secret.state
            }
        }
    }

    private func loadHotkey(key: String, legacyKey: String?, fallback: HotkeyShortcut) -> HotkeyShortcut {
        if let data = dataValue(forKey: key),
           let decodedShortcut = try? decoder.decode(HotkeyShortcut.self, from: data) {
            return decodedShortcut
        }

        if let legacyKey,
           let data = dataValue(forKey: legacyKey),
           let decodedShortcut = try? decoder.decode(HotkeyShortcut.self, from: data) {
            defaults.set(data, forKey: key)
            return decodedShortcut
        }

        return fallback
    }

    @discardableResult
    private func persistSecret(_ value: String, for slot: SecretSlot) -> APIKeyPersistenceState {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedValue.isEmpty {
            try? keychainService.deleteValue(service: slot.service, account: slot.account)
            slot.legacyServices.forEach { service in
                try? keychainService.deleteValue(service: service, account: slot.account)
            }
            sessionOnlySecrets.removeValue(forKey: slot)
            return .empty
        }

        do {
            try keychainService.setString(trimmedValue, service: slot.service, account: slot.account)
            slot.legacyServices.forEach { service in
                try? keychainService.deleteValue(service: service, account: slot.account)
            }
            sessionOnlySecrets.removeValue(forKey: slot)
            return .keychain
        } catch {
            sessionOnlySecrets[slot] = trimmedValue
            return .sessionOnly
        }
    }

    private func loadSecret(
        for slot: SecretSlot,
        allowInteraction: Bool,
        includeLegacyServices: Bool
    ) -> (value: String, state: APIKeyPersistenceState) {
        do {
            if let keychainValue = try keychainService.string(
                forService: slot.service,
                account: slot.account,
                allowInteraction: allowInteraction
            ),
               !keychainValue.isEmpty {
                return (keychainValue, .keychain)
            }

            if includeLegacyServices {
                for legacyService in slot.legacyServices {
                    if let legacyValue = try keychainService.string(
                        forService: legacyService,
                        account: slot.account,
                        allowInteraction: allowInteraction
                    ),
                       !legacyValue.isEmpty {
                        _ = persistSecret(legacyValue, for: slot)
                        return (legacyValue, .keychain)
                    }
                }
            }
        } catch {
            if let sessionOnlyValue = sessionOnlySecrets[slot], !sessionOnlyValue.isEmpty {
                return (sessionOnlyValue, .sessionOnly)
            }

            return ("", .empty)
        }

        if let sessionOnlyValue = sessionOnlySecrets[slot], !sessionOnlyValue.isEmpty {
            return (sessionOnlyValue, .sessionOnly)
        }

        return ("", .empty)
    }

    private func persistHotkey(_ shortcut: HotkeyShortcut, key: String) {
        guard let data = try? encoder.encode(shortcut) else {
            return
        }

        defaults.set(data, forKey: key)
    }

    private func storageDescription(for state: APIKeyPersistenceState, empty: String) -> String {
        switch state {
        case .empty:
            return empty
        case .keychain:
            return "Stored securely in your macOS Keychain."
        case .sessionOnly:
            return "Keychain storage was unavailable, so this value is only kept in memory until you quit BugNarrator."
        }
    }

    private func mask(secret: String, emptyPlaceholder: String) -> String {
        guard !secret.isEmpty else {
            return emptyPlaceholder
        }

        let suffixCount = min(4, secret.count)
        let suffix = secret.suffix(suffixCount)
        return "••••••••\(suffix)"
    }

    private func normalizeOptional(_ value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func stringValue(forKey key: String, legacyKeys: [String] = []) -> String? {
        if let value = defaults.string(forKey: key) {
            return value
        }

        for legacyKey in legacyKeys {
            if let value = defaults.string(forKey: legacyKey) {
                defaults.set(value, forKey: key)
                return value
            }
        }

        let keysToSearch = [key] + legacyKeys
        for domainName in legacyDefaultsDomains {
            guard let domain = defaults.persistentDomain(forName: domainName) else {
                continue
            }

            for candidateKey in keysToSearch {
                if let value = domain[candidateKey] as? String {
                    defaults.set(value, forKey: key)
                    return value
                }
            }
        }

        return nil
    }

    private func boolValue(forKey key: String, legacyKeys: [String] = []) -> Bool? {
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }

        for legacyKey in legacyKeys where defaults.object(forKey: legacyKey) != nil {
            let value = defaults.bool(forKey: legacyKey)
            defaults.set(value, forKey: key)
            return value
        }

        let keysToSearch = [key] + legacyKeys
        for domainName in legacyDefaultsDomains {
            guard let domain = defaults.persistentDomain(forName: domainName) else {
                continue
            }

            for candidateKey in keysToSearch {
                if let value = domain[candidateKey] as? Bool {
                    defaults.set(value, forKey: key)
                    return value
                }
            }
        }

        return nil
    }

    private func dataValue(forKey key: String) -> Data? {
        if let data = defaults.data(forKey: key) {
            return data
        }

        for domainName in legacyDefaultsDomains {
            guard let domain = defaults.persistentDomain(forName: domainName),
                  let data = domain[key] as? Data else {
                continue
            }

            defaults.set(data, forKey: key)
            return data
        }

        return nil
    }
}

private enum SecretSlot: Hashable, CaseIterable {
    case openAI
    case github
    case jira

    var service: String {
        switch self {
        case .openAI:
            return "BugNarrator.OpenAI"
        case .github:
            return "BugNarrator.GitHub"
        case .jira:
            return "BugNarrator.Jira"
        }
    }

    var legacyServices: [String] {
        switch self {
        case .openAI:
            return ["SessionMic.OpenAI", "FeedbackMic.OpenAI"]
        case .github:
            return ["SessionMic.GitHub", "FeedbackMic.GitHub"]
        case .jira:
            return ["SessionMic.Jira", "FeedbackMic.Jira"]
        }
    }

    var account: String {
        switch self {
        case .openAI:
            return "openai-api-key"
        case .github:
            return "github-token"
        case .jira:
            return "jira-api-token"
        }
    }
}

private enum Keys {
    static let preferredModel = "settings.preferredModel"
    static let languageHint = "settings.languageHint"
    static let transcriptionPrompt = "settings.transcriptionPrompt"
    static let issueExtractionModel = "settings.issueExtractionModel"
    static let legacyIssueExtractionModel = "settings.reviewProcessingModel"
    static let autoCopyTranscript = "settings.autoCopyTranscript"
    static let autoSaveTranscript = "settings.autoSaveTranscript"
    static let autoExtractIssues = "settings.autoExtractIssues"
    static let recordingHotkeyShortcut = "settings.recordingHotkeyShortcut"
    static let legacyRecordingHotkeyShortcut = "settings.hotkeyShortcut"
    static let markerHotkeyShortcut = "settings.markerHotkeyShortcut"
    static let screenshotHotkeyShortcut = "settings.screenshotHotkeyShortcut"
    static let githubRepositoryOwner = "settings.githubRepositoryOwner"
    static let githubRepositoryName = "settings.githubRepositoryName"
    static let githubDefaultLabels = "settings.githubDefaultLabels"
    static let jiraBaseURL = "settings.jiraBaseURL"
    static let jiraEmail = "settings.jiraEmail"
    static let jiraProjectKey = "settings.jiraProjectKey"
    static let jiraIssueType = "settings.jiraIssueType"
    static let debugMode = "settings.debugMode"
}

enum APIKeyPersistenceState: Equatable {
    case empty
    case keychain
    case sessionOnly
}
