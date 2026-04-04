import Combine
import Foundation

final class SettingsStore: ObservableObject {
    private let logger = DiagnosticsLogger(category: .settings)

    @Published var apiKey: String = "" {
        didSet {
            guard hasLoaded else { return }
            apiKeyPersistenceState = persistSecret(apiKey, for: .openAI)
        }
    }

    @Published private(set) var jiraEmailPersistenceState: APIKeyPersistenceState = .empty

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

    @Published var openAtStartup: Bool = false {
        didSet {
            guard hasLoaded, !isSynchronizingLaunchAtLogin else { return }
            updateLaunchAtLoginPreference(enabled: openAtStartup)
        }
    }

    @Published var startRecordingHotkeyShortcut: HotkeyShortcut = .disabled {
        didSet {
            guard hasLoaded else { return }
            hotkeyDidChange(.startRecording, previousShortcut: oldValue)
        }
    }

    @Published var stopRecordingHotkeyShortcut: HotkeyShortcut = .disabled {
        didSet {
            guard hasLoaded else { return }
            hotkeyDidChange(.stopRecording, previousShortcut: oldValue)
        }
    }

    @Published var screenshotHotkeyShortcut: HotkeyShortcut = .disabled {
        didSet {
            guard hasLoaded else { return }
            hotkeyDidChange(.captureScreenshot, previousShortcut: oldValue)
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
            jiraEmailPersistenceState = persistSecret(jiraEmail, for: .jiraEmail)
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
            BugNarratorDiagnostics.setDebugModeEnabled(debugMode)
            logger.info(
                "debug_mode_changed",
                debugMode
                    ? "Debug mode was enabled. Verbose diagnostics are now recorded locally."
                    : "Debug mode was disabled. BugNarrator will keep logging info, warnings, and errors.",
                metadata: ["debug_mode": debugMode ? "enabled" : "disabled"]
            )
        }
    }

    @Published private(set) var apiKeyPersistenceState: APIKeyPersistenceState = .empty
    @Published private(set) var githubTokenPersistenceState: APIKeyPersistenceState = .empty
    @Published private(set) var jiraTokenPersistenceState: APIKeyPersistenceState = .empty
    @Published private(set) var hotkeyConflictMessage: String?
    @Published private(set) var openAtStartupSupported = true
    @Published private(set) var openAtStartupStatusMessage: String?
    @Published private(set) var openAtStartupStatusTone: SettingsCalloutTone = .secondary

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hotkeyAssignments: [(action: HotkeyAction, shortcut: HotkeyShortcut)] {
        [
            (.startRecording, startRecordingHotkeyShortcut),
            (.stopRecording, stopRecordingHotkeyShortcut),
            (.captureScreenshot, screenshotHotkeyShortcut)
        ]
    }

    var maskedAPIKey: String {
        mask(
            secret: trimmedAPIKey,
            persistenceState: apiKeyPersistenceState,
            emptyPlaceholder: "No key saved",
            lockedPlaceholder: "Saved key locked"
        )
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
        mask(
            secret: trimmedGitHubToken,
            persistenceState: githubTokenPersistenceState,
            emptyPlaceholder: "No token saved",
            lockedPlaceholder: "Saved token locked"
        )
    }

    var githubTokenStorageDescription: String {
        storageDescription(
            for: githubTokenPersistenceState,
            empty: "Add a GitHub personal access token if you want to try the experimental GitHub Issues export."
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
        mask(
            secret: trimmedJiraAPIToken,
            persistenceState: jiraTokenPersistenceState,
            emptyPlaceholder: "No token saved",
            lockedPlaceholder: "Saved token locked"
        )
    }

    var jiraTokenStorageDescription: String {
        storageDescription(
            for: jiraTokenPersistenceState,
            empty: "Add Jira Cloud credentials if you want to try the experimental Jira export."
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
    private let launchAtLoginService: any LaunchAtLoginControlling
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let legacyDefaultsDomains: [String]
    private var hasLoaded = false
    private var isSynchronizingHotkeys = false
    private var isSynchronizingLaunchAtLogin = false
    private var sessionOnlySecrets: [SecretSlot: String] = [:]

    init(
        defaults: UserDefaults = .standard,
        keychainService: KeychainServicing = KeychainService(),
        launchAtLoginService: (any LaunchAtLoginControlling)? = nil,
        legacyDefaultsDomains: [String]? = nil
    ) {
        self.defaults = defaults
        self.keychainService = keychainService
        self.launchAtLoginService = launchAtLoginService ?? Self.defaultLaunchAtLoginService()
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
        logger.debug("refresh_all_secrets", "Refreshing stored secrets after a user-initiated action.")
        reloadSecrets(slots: Array(SecretSlot.allCases), allowInteraction: true, includeLegacyServices: true)
    }

    func refreshOpenAISecretForUserInitiatedAccess() {
        logger.debug("refresh_openai_secret", "Refreshing the OpenAI API key after a user-initiated action.")
        reloadSecrets(slots: [.openAI], allowInteraction: true, includeLegacyServices: true)
    }

    func refreshExportSecretsForUserInitiatedAccess() {
        logger.debug("refresh_export_secrets", "Refreshing export credentials after a user-initiated action.")
        reloadSecrets(slots: [.github, .jiraEmail, .jira], allowInteraction: true, includeLegacyServices: true)
    }

    func removeAPIKey() {
        apiKey = ""
        logger.info("remove_openai_key", "The OpenAI API key was removed from local storage.")
    }

    func removeGitHubToken() {
        githubToken = ""
        logger.info("remove_github_token", "The GitHub export token was removed from local storage.")
    }

    func removeJiraAPIToken() {
        jiraAPIToken = ""
        logger.info("remove_jira_token", "The Jira API token was removed from local storage.")
    }

    private func load() {
        logger.debug("load_settings", "Loading persisted settings and secure credentials.")
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
        syncLaunchAtLoginState(launchAtLoginService.currentStatus())

        startRecordingHotkeyShortcut = loadHotkey(
            key: Keys.startRecordingHotkeyShortcut,
            legacyKeys: [Keys.legacyStartRecordingHotkeyShortcut, Keys.legacyRecordingHotkeyShortcut]
        )
        stopRecordingHotkeyShortcut = loadHotkey(
            key: Keys.stopRecordingHotkeyShortcut,
            legacyKeys: []
        )
        screenshotHotkeyShortcut = loadHotkey(
            key: Keys.screenshotHotkeyShortcut,
            legacyKeys: []
        )
        removeObsoleteMarkerHotkeyIfNeeded()

        githubRepositoryOwner = stringValue(forKey: Keys.githubRepositoryOwner) ?? ""
        githubRepositoryName = stringValue(forKey: Keys.githubRepositoryName) ?? ""
        githubDefaultLabels = stringValue(forKey: Keys.githubDefaultLabels) ?? ""

        jiraBaseURL = stringValue(forKey: Keys.jiraBaseURL) ?? ""
        jiraProjectKey = stringValue(forKey: Keys.jiraProjectKey) ?? ""
        jiraIssueType = stringValue(forKey: Keys.jiraIssueType) ?? "Task"
        migrateLegacyPlaintextJiraEmailIfNeeded()

        debugMode = boolValue(forKey: Keys.debugMode) ?? false
        migrateLegacyBuiltInHotkeysIfNeeded()
        normalizeLoadedHotkeyConflicts()
        BugNarratorDiagnostics.setDebugModeEnabled(debugMode)
        logger.info(
            "settings_loaded",
            "Settings finished loading.",
            metadata: [
                "debug_mode": debugMode ? "enabled" : "disabled",
                "has_openai_key": hasAPIKey ? "yes" : "no",
                "has_github_token": hasGitHubToken ? "yes" : "no",
                "has_jira_token": hasJiraAPIToken ? "yes" : "no",
                "launch_at_login": openAtStartup ? "enabled" : "disabled",
                "launch_at_login_supported": openAtStartupSupported ? "yes" : "no"
            ]
        )
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
            case .jiraEmail:
                jiraEmail = secret.value
                jiraEmailPersistenceState = secret.state
            case .jira:
                jiraAPIToken = secret.value
                jiraTokenPersistenceState = secret.state
            }
        }

        logger.debug(
            "secrets_reloaded",
            "Secure values were reloaded from Keychain or memory.",
            metadata: [
                "allow_interaction": allowInteraction ? "yes" : "no",
                "includes_legacy_services": includeLegacyServices ? "yes" : "no",
                "slot_count": "\(slots.count)"
            ]
        )
    }

    private func loadHotkey(key: String, legacyKeys: [String]) -> HotkeyShortcut {
        if let data = dataValue(forKey: key),
           let decodedShortcut = try? decoder.decode(HotkeyShortcut.self, from: data) {
            return decodedShortcut
        }

        for legacyKey in legacyKeys {
            if let data = dataValue(forKey: legacyKey),
               let decodedShortcut = try? decoder.decode(HotkeyShortcut.self, from: data) {
                defaults.set(data, forKey: key)
                return decodedShortcut
            }
        }

        return .disabled
    }

    private func hotkeyDidChange(_ changedAction: HotkeyAction, previousShortcut: HotkeyShortcut) {
        let changedShortcut = shortcut(for: changedAction)

        if isSynchronizingHotkeys {
            persistHotkey(changedShortcut, key: storageKey(for: changedAction))
            return
        }

        isSynchronizingHotkeys = true
        defer { isSynchronizingHotkeys = false }

        if changedShortcut.isEnabled,
           let conflictingAction = HotkeyAction.allCases.first(where: {
               $0 != changedAction && shortcut(for: $0) == changedShortcut
           }) {
            logger.warning(
                "hotkey_conflict_rejected",
                "A conflicting hotkey assignment was rejected.",
                metadata: [
                    "action": changedAction.title,
                    "conflict_action": conflictingAction.title,
                    "shortcut": changedShortcut.displayString
                ]
            )
            hotkeyConflictMessage = "\(changedShortcut.displayString) is already assigned to \(conflictingAction.title). Clear it first or choose a different shortcut."
            setShortcut(previousShortcut, for: changedAction)
            return
        }

        hotkeyConflictMessage = nil
        persistHotkey(changedShortcut, key: storageKey(for: changedAction))
    }

    private func migrateLegacyBuiltInHotkeysIfNeeded() {
        guard defaults.object(forKey: Keys.didMigrateLegacyBuiltInHotkeys) == nil else {
            return
        }

        var clearedActions: [String] = []

        for action in HotkeyAction.allCases {
            guard let legacyBuiltInShortcut = action.legacyBuiltInShortcut,
                  shortcut(for: action) == legacyBuiltInShortcut else {
                continue
            }

            setShortcut(.disabled, for: action)
            persistHotkey(.disabled, key: storageKey(for: action))
            clearedActions.append(action.title)
        }

        defaults.set(true, forKey: Keys.didMigrateLegacyBuiltInHotkeys)

        if !clearedActions.isEmpty {
            logger.info(
                "legacy_hotkey_defaults_cleared",
                "Cleared previously built-in hotkey defaults so shortcuts start unassigned.",
                metadata: ["cleared_actions": clearedActions.joined(separator: ",")]
            )
        }
    }

    private func normalizeLoadedHotkeyConflicts() {
        isSynchronizingHotkeys = true

        var seenShortcuts = Set<HotkeyShortcut>()
        for action in HotkeyAction.allCases {
            let shortcut = shortcut(for: action)
            guard shortcut.isEnabled else {
                persistHotkey(shortcut, key: storageKey(for: action))
                continue
            }

            if seenShortcuts.contains(shortcut) {
                setShortcut(.disabled, for: action)
                continue
            }

            seenShortcuts.insert(shortcut)
            persistHotkey(shortcut, key: storageKey(for: action))
        }

        isSynchronizingHotkeys = false
    }

    private func shortcut(for action: HotkeyAction) -> HotkeyShortcut {
        switch action {
        case .startRecording:
            return startRecordingHotkeyShortcut
        case .stopRecording:
            return stopRecordingHotkeyShortcut
        case .captureScreenshot:
            return screenshotHotkeyShortcut
        }
    }

    private func setShortcut(_ shortcut: HotkeyShortcut, for action: HotkeyAction) {
        switch action {
        case .startRecording:
            startRecordingHotkeyShortcut = shortcut
        case .stopRecording:
            stopRecordingHotkeyShortcut = shortcut
        case .captureScreenshot:
            screenshotHotkeyShortcut = shortcut
        }
    }

    private func storageKey(for action: HotkeyAction) -> String {
        switch action {
        case .startRecording:
            return Keys.startRecordingHotkeyShortcut
        case .stopRecording:
            return Keys.stopRecordingHotkeyShortcut
        case .captureScreenshot:
            return Keys.screenshotHotkeyShortcut
        }
    }

    private func removeObsoleteMarkerHotkeyIfNeeded() {
        guard defaults.object(forKey: Keys.markerHotkeyShortcut) != nil else {
            return
        }

        defaults.removeObject(forKey: Keys.markerHotkeyShortcut)
        logger.info(
            "removed_obsolete_marker_hotkey",
            "Removed the obsolete standalone marker hotkey assignment during settings load."
        )
    }

    private func updateLaunchAtLoginPreference(enabled: Bool) {
        do {
            let status = try launchAtLoginService.setEnabled(enabled)
            syncLaunchAtLoginState(status)
            logger.info(
                "launch_at_login_updated",
                enabled
                    ? "BugNarrator will open automatically at login."
                    : "BugNarrator will no longer open automatically at login.",
                metadata: ["status": status.logValue]
            )
        } catch {
            let status = launchAtLoginService.currentStatus()
            syncLaunchAtLoginState(status)
            openAtStartupStatusTone = .error
            openAtStartupStatusMessage = "BugNarrator couldn't update the Open at Startup setting. \(error.localizedDescription)"
            logger.error(
                "launch_at_login_update_failed",
                "Updating the launch-at-login setting failed.",
                metadata: [
                    "requested_state": enabled ? "enabled" : "disabled",
                    "status": status.logValue
                ]
            )
        }
    }

    private func syncLaunchAtLoginState(_ status: LaunchAtLoginStatus) {
        isSynchronizingLaunchAtLogin = true
        openAtStartup = status.isEnabled
        isSynchronizingLaunchAtLogin = false

        openAtStartupSupported = status.isAvailable
        openAtStartupStatusMessage = status.message

        switch status {
        case .disabled, .enabled:
            openAtStartupStatusTone = .secondary
        case .requiresApproval, .unavailable:
            openAtStartupStatusTone = .warning
        }
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
            logger.info(
                "secret_cleared",
                "A secure value was cleared from persistent storage.",
                metadata: ["slot": slot.redactionSafeName]
            )
            return .empty
        }

        do {
            try keychainService.setString(trimmedValue, service: slot.service, account: slot.account)
            slot.legacyServices.forEach { service in
                try? keychainService.deleteValue(service: service, account: slot.account)
            }
            sessionOnlySecrets.removeValue(forKey: slot)
            logger.info(
                "secret_persisted",
                "A secure value was saved to Keychain.",
                metadata: ["slot": slot.redactionSafeName]
            )
            return .keychain
        } catch {
            sessionOnlySecrets[slot] = trimmedValue
            logger.warning(
                "secret_persisted_in_memory",
                "Keychain storage was unavailable, so a secure value is only kept in memory for this run.",
                metadata: ["slot": slot.redactionSafeName]
            )
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
                logger.warning(
                    "secret_fallback_to_memory",
                    "Keychain access failed, so BugNarrator fell back to an in-memory secure value.",
                    metadata: ["slot": slot.redactionSafeName]
                )
                return (sessionOnlyValue, .sessionOnly)
            }

            if case KeychainError.interactionRequired = error {
                logger.debug(
                    "secret_locked",
                    "A secure value remains in Keychain, but BugNarrator skipped the unlock prompt until a user-initiated action needs it.",
                    metadata: [
                        "slot": slot.redactionSafeName,
                        "allow_interaction": allowInteraction ? "yes" : "no"
                    ]
                )
                return ("", .keychainLocked)
            }

            logger.debug(
                "secret_unavailable",
                "A secure value was unavailable during reload.",
                metadata: [
                    "slot": slot.redactionSafeName,
                    "allow_interaction": allowInteraction ? "yes" : "no"
                ]
            )
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

    private func migrateLegacyPlaintextJiraEmailIfNeeded() {
        let legacyEmail = stringValue(forKey: Keys.jiraEmail)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !legacyEmail.isEmpty else {
            defaults.removeObject(forKey: Keys.jiraEmail)
            return
        }

        if jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            jiraEmail = legacyEmail
            jiraEmailPersistenceState = persistSecret(legacyEmail, for: .jiraEmail)
        }

        defaults.removeObject(forKey: Keys.jiraEmail)
        logger.info(
            "migrated_plaintext_jira_email",
            "Migrated the Jira export email out of plain preferences storage.",
            metadata: ["persistence_state": String(describing: jiraEmailPersistenceState)]
        )
    }

    private func storageDescription(for state: APIKeyPersistenceState, empty: String) -> String {
        switch state {
        case .empty:
            return empty
        case .keychain:
            return "Stored securely in your macOS Keychain."
        case .keychainLocked:
            return "Stored in your macOS Keychain. BugNarrator will only prompt to unlock it when you validate the key or run an action that needs it."
        case .sessionOnly:
            return "Keychain storage was unavailable, so this value is only kept in memory until you quit BugNarrator."
        }
    }

    private func mask(
        secret: String,
        persistenceState: APIKeyPersistenceState,
        emptyPlaceholder: String,
        lockedPlaceholder: String
    ) -> String {
        guard !secret.isEmpty else {
            return persistenceState == .keychainLocked ? lockedPlaceholder : emptyPlaceholder
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

    private static func defaultLaunchAtLoginService() -> any LaunchAtLoginControlling {
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTestBundlePath"] != nil ||
            environment["XCTestSessionIdentifier"] != nil {
            return TestingLaunchAtLoginService()
        }

        return SystemLaunchAtLoginService()
    }
}

private enum SecretSlot: Hashable, CaseIterable {
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
            return ["SessionMic.OpenAI", "FeedbackMic.OpenAI"]
        case .github:
            return ["SessionMic.GitHub", "FeedbackMic.GitHub"]
        case .jiraEmail:
            return ["SessionMic.Jira", "FeedbackMic.Jira"]
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

private enum Keys {
    static let preferredModel = "settings.preferredModel"
    static let languageHint = "settings.languageHint"
    static let transcriptionPrompt = "settings.transcriptionPrompt"
    static let issueExtractionModel = "settings.issueExtractionModel"
    static let legacyIssueExtractionModel = "settings.reviewProcessingModel"
    static let autoCopyTranscript = "settings.autoCopyTranscript"
    static let autoSaveTranscript = "settings.autoSaveTranscript"
    static let autoExtractIssues = "settings.autoExtractIssues"
    static let startRecordingHotkeyShortcut = "settings.startRecordingHotkeyShortcut"
    static let legacyRecordingHotkeyShortcut = "settings.hotkeyShortcut"
    static let legacyStartRecordingHotkeyShortcut = "settings.recordingHotkeyShortcut"
    static let stopRecordingHotkeyShortcut = "settings.stopRecordingHotkeyShortcut"
    static let markerHotkeyShortcut = "settings.markerHotkeyShortcut"
    static let screenshotHotkeyShortcut = "settings.screenshotHotkeyShortcut"
    static let didMigrateLegacyBuiltInHotkeys = "settings.didMigrateLegacyBuiltInHotkeys"
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
    case keychainLocked
    case sessionOnly
}

enum SettingsCalloutTone: Equatable {
    case secondary
    case warning
    case error
}
