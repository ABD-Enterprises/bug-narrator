import Combine
import Foundation

struct AIModelChoice: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
}

final class SettingsStore: ObservableObject {
    static let defaultLegacyDefaultsDomains = [
        "com.abdenterprises.sessionmic"
    ]

    private static let openAITranscriptionModel = "whisper-1"
    private static let defaultLanguageHint = "en"
    private static let parakeetTranscriptionModel = "parakeet-tdt-0.6b-v3"
    private static let openAIIssueExtractionModel = "gpt-4.1-mini"
    private static let openAITranscriptionModelChoices = [
        AIModelChoice(
            id: "whisper-1",
            title: "Whisper",
            detail: "Stable default"
        ),
        AIModelChoice(
            id: "gpt-4o-mini-transcribe",
            title: "GPT-4o mini Transcribe",
            detail: "Lower cost, newer speech-to-text"
        ),
        AIModelChoice(
            id: "gpt-4o-transcribe",
            title: "GPT-4o Transcribe",
            detail: "Higher accuracy speech-to-text"
        ),
        AIModelChoice(
            id: "gpt-4o-transcribe-diarize",
            title: "GPT-4o Transcribe Diarize",
            detail: "Adds speaker labels"
        )
    ]
    private static let parakeetTranscriptionModelChoices = [
        AIModelChoice(
            id: parakeetTranscriptionModel,
            title: "Parakeet TDT 0.6B v3",
            detail: "Local transcription server"
        )
    ]
    private static let openAIIssueExtractionModelChoices = [
        AIModelChoice(
            id: "gpt-4.1-mini",
            title: "GPT-4.1 mini",
            detail: "Recommended default"
        ),
        AIModelChoice(
            id: "gpt-4.1-nano",
            title: "GPT-4.1 nano",
            detail: "Fastest and lowest cost"
        ),
        AIModelChoice(
            id: "gpt-4.1",
            title: "GPT-4.1",
            detail: "Higher quality issue extraction"
        )
    ]

    private let logger = DiagnosticsLogger(category: .settings)

    var apiKey: String = "" {
        willSet {
            guard hasLoaded, apiKey != newValue else { return }
            objectWillChange.send()
        }
        didSet {
            guard hasLoaded else { return }
            secretDidChange(.openAI)
        }
    }

    @Published private(set) var jiraEmailPersistenceState: APIKeyPersistenceState = .empty

    @Published var openAIBaseURL: String = "" {
        didSet {
            guard hasLoaded else { return }
            defaults.set(openAIBaseURL, forKey: Keys.openAIBaseURL)
        }
    }

    @Published var aiProvider: AIProvider = .openAI {
        didSet {
            guard hasLoaded else { return }
            defaults.set(aiProvider.rawValue, forKey: Keys.aiProvider)
            normalizeTranscriptionModelForCurrentProvider(persist: true)
            normalizeIssueExtractionModelForCurrentProvider(persist: true)
            normalizeIssueExtractionAvailabilityForCurrentProvider(persist: true)
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

    @Published var systemAudioCaptureEnabled: Bool = false {
        didSet {
            guard hasLoaded else { return }
            recordingPreferences.persist(systemAudioCaptureEnabled: systemAudioCaptureEnabled)
            if !systemAudioCaptureEnabled, recordingAudioSource.usesSystemAudio {
                recordingAudioSource = .microphone
            }
        }
    }

    @Published var recordingAudioSource: RecordingAudioSource = .microphone {
        didSet {
            guard hasLoaded else { return }
            recordingPreferences.persist(recordingAudioSource: recordingAudioSource)
        }
    }

    @Published var hasAcceptedSystemAudioRecordingConsent: Bool = false {
        didSet {
            guard hasLoaded else { return }
            recordingPreferences.persist(hasAcceptedSystemAudioRecordingConsent: hasAcceptedSystemAudioRecordingConsent)
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
            secretDidChange(.github)
        }
    }

    @Published var githubRepositoryOwner: String = "" {
        didSet {
            guard hasLoaded else { return }
            if githubRepositoryOwner.compare(oldValue, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame {
                githubRepositoryID = ""
            }
            trackerExportSettings.persist(githubRepositoryOwner: githubRepositoryOwner)
        }
    }

    @Published var githubRepositoryName: String = "" {
        didSet {
            guard hasLoaded else { return }
            if githubRepositoryName.compare(oldValue, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame {
                githubRepositoryID = ""
            }
            trackerExportSettings.persist(githubRepositoryName: githubRepositoryName)
        }
    }

    @Published var githubRepositoryID: String = "" {
        didSet {
            guard hasLoaded else { return }
            trackerExportSettings.persist(githubRepositoryID: githubRepositoryID)
        }
    }

    @Published var githubDefaultLabels: String = "" {
        didSet {
            guard hasLoaded else { return }
            trackerExportSettings.persist(githubDefaultLabels: githubDefaultLabels)
        }
    }

    @Published var jiraBaseURL: String = "" {
        didSet {
            guard hasLoaded else { return }
            trackerExportSettings.persist(jiraBaseURL: jiraBaseURL)
        }
    }

    @Published var jiraEmail: String = "" {
        didSet {
            guard hasLoaded else { return }
            secretDidChange(.jiraEmail)
        }
    }

    @Published var jiraAPIToken: String = "" {
        didSet {
            guard hasLoaded else { return }
            secretDidChange(.jira)
        }
    }

    @Published var jiraProjectKey: String = "" {
        didSet {
            guard hasLoaded else { return }
            if normalizedJiraProjectKey != oldValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
                jiraProjectID = ""
            }
            trackerExportSettings.persist(jiraProjectKey: jiraProjectKey)
        }
    }

    @Published var jiraIssueType: String = "" {
        didSet {
            guard hasLoaded else { return }
            if normalizedJiraIssueType.compare(oldValue.trimmingCharacters(in: .whitespacesAndNewlines), options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame {
                jiraIssueTypeID = ""
            }
            trackerExportSettings.persist(jiraIssueType: jiraIssueType)
        }
    }

    @Published var jiraProjectID: String = "" {
        didSet {
            guard hasLoaded else { return }
            trackerExportSettings.persist(jiraProjectID: jiraProjectID)
        }
    }

    @Published var jiraIssueTypeID: String = "" {
        didSet {
            guard hasLoaded else { return }
            trackerExportSettings.persist(jiraIssueTypeID: jiraIssueTypeID)
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

    @Published var operationalTelemetryEnabled: Bool = true {
        didSet {
            guard hasLoaded else { return }
            defaults.set(operationalTelemetryEnabled, forKey: Keys.operationalTelemetryEnabled)
        }
    }

    @Published var autoShowChangelogOnUpdate: Bool = true {
        didSet {
            guard hasLoaded else { return }
            defaults.set(autoShowChangelogOnUpdate, forKey: Keys.autoShowChangelogOnUpdate)
        }
    }

    @Published var suppressSystemAudioExplainer: Bool = false {
        didSet {
            guard hasLoaded else { return }
            recordingPreferences.persist(suppressSystemAudioExplainer: suppressSystemAudioExplainer)
        }
    }

    /// Whether to show the one-time system-audio explainer before starting a
    /// recording. `acknowledged` is the transient per-attempt flag the caller
    /// sets after the user dismisses the sheet, so re-entry does not loop.
    func shouldShowSystemAudioExplainer(for source: RecordingAudioSource, acknowledged: Bool) -> Bool {
        source.usesSystemAudio && !suppressSystemAudioExplainer && !acknowledged
    }

    /// Decides whether to auto-present the changelog once after a version bump.
    /// Brand-new installs (no recorded version and no existing user state) defer
    /// to onboarding instead of showing the changelog.
    func shouldAutoShowChangelog(currentVersion: String, hasExistingUserState: Bool) -> Bool {
        guard autoShowChangelogOnUpdate else { return false }
        if let lastShown = stringValue(forKey: Keys.lastShownChangelogVersion) {
            return lastShown != currentVersion
        }
        return hasExistingUserState
    }

    func markChangelogShown(version: String) {
        defaults.set(version, forKey: Keys.lastShownChangelogVersion)
    }

    @Published private(set) var apiKeyPersistenceState: APIKeyPersistenceState = .empty
    @Published private(set) var githubTokenPersistenceState: APIKeyPersistenceState = .empty
    @Published private(set) var jiraTokenPersistenceState: APIKeyPersistenceState = .empty
    @Published private(set) var hotkeyConflictMessage: String?
    @Published private(set) var conflictingHotkeyAction: HotkeyAction?
    @Published private(set) var openAtStartupSupported = true
    @Published private(set) var openAtStartupStatusMessage: String?
    @Published private(set) var openAtStartupStatusTone: SettingsCalloutTone = .secondary

    var openAtStartupControlIsEnabled: Bool {
        openAtStartupSupported
    }

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

    /// The action's suggested default, but only when it is enabled and not
    /// already assigned to a different action — so a suggestion never collides.
    func suggestedShortcutIfAvailable(for action: HotkeyAction) -> HotkeyShortcut? {
        guard let suggestion = action.suggestedShortcut, suggestion.isEnabled else {
            return nil
        }

        let assignedElsewhere = hotkeyAssignments.contains {
            $0.action != action && $0.shortcut == suggestion
        }
        return assignedElsewhere ? nil : suggestion
    }


    var selectedAIProviderCredentialPersistenceState: APIKeyPersistenceState {
        guard aiProvider != .parakeetLocal else {
            return .empty
        }

        if hasPendingSecretChanges(for: .openAI) {
            return apiKeyPersistenceState
        }

        guard credentialIsAvailableForUserAction(
            value: trimmedAPIKey,
            persistenceState: apiKeyPersistenceState
        ) else {
            return .empty
        }

        return aiProviderCredentialMatchesCurrentProvider(
            allowsLegacyOpenAICredential: aiProvider == .openAI
        ) ? apiKeyPersistenceState : .empty
    }

    var hasSelectedAIProviderCredential: Bool {
        let persistenceState = selectedAIProviderCredentialPersistenceState
        guard persistenceState != .empty else {
            return false
        }

        return credentialIsAvailableForUserAction(
            value: trimmedAPIKey,
            persistenceState: persistenceState
        )
    }




    var openAIBaseURLValue: URL {
        Self.normalizedOpenAIBaseURL(from: openAIBaseURL, provider: aiProvider)
    }

    static let providerFallbackBaseURLs: [AIProvider: URL] = {
        var table: [AIProvider: URL] = [:]
        for provider in AIProvider.allCases {
            guard let url = URL(string: provider.baseURLPlaceholder) else {
                preconditionFailure(
                    "AIProvider.\(provider.rawValue).baseURLPlaceholder is not a parseable URL. " +
                    "Update the placeholder or add an explicit fallback in providerFallbackBaseURLs."
                )
            }
            table[provider] = url
        }
        return table
    }()

    static func fallbackBaseURL(for provider: AIProvider) -> URL {
        // providerFallbackBaseURLs is built at type init from AIProvider.allCases and asserts
        // every case is parseable, so this subscript is total.
        providerFallbackBaseURLs[provider] ?? providerFallbackBaseURLs[.openAI]!
    }

    static func normalizedOpenAIBaseURL(
        from rawValue: String,
        provider: AIProvider = .openAI
    ) -> URL {
        let fallback = fallbackBaseURL(for: provider)
        if provider == .parakeetLocal {
            return fallback
        }

        let trimmedValue = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !trimmedValue.isEmpty else {
            return fallback
        }

        let defaultScheme = fallback.scheme ?? "https"
        let candidate = trimmedValue.contains("://") ? trimmedValue : "\(defaultScheme)://\(trimmedValue)"
        guard var components = URLComponents(string: candidate),
              components.host?.isEmpty == false else {
            return fallback
        }

        if components.scheme?.isEmpty != false {
            components.scheme = "https"
        }

        if components.path == "/" {
            components.path = ""
        }

        return components.url ?? fallback
    }

    /// Whether `host` denotes a loopback / private / link-local / `.local`
    /// endpoint. Plaintext HTTP to such a host is acceptable because the traffic
    /// stays on the machine or the trusted local network; plaintext HTTP to any
    /// other host would send the API key and transcript text over the public
    /// internet unencrypted.
    static func isLocalEndpointHost(_ host: String) -> Bool {
        let lowered = host
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

        if lowered == "localhost" || lowered.hasSuffix(".localhost") { return true }
        if lowered.hasSuffix(".local") { return true }
        // Single-label hostnames (e.g. "lmstudio") never resolve on public DNS.
        if !lowered.contains(".") && !lowered.contains(":") { return true }
        // IPv6 loopback / link-local.
        if lowered == "::1" || lowered.hasPrefix("fe80:") { return true }

        let octets = lowered.split(separator: ".").compactMap { UInt8($0) }
        if octets.count == 4, lowered.allSatisfy({ $0.isNumber || $0 == "." }) {
            switch (octets[0], octets[1]) {
            case (127, _): return true        // loopback 127.0.0.0/8
            case (10, _): return true         // private 10.0.0.0/8
            case (192, 168): return true      // private 192.168.0.0/16
            case (169, 254): return true      // link-local 169.254.0.0/16
            case (172, 16...31): return true  // private 172.16.0.0/12
            default: return false
            }
        }
        return false
    }

    /// A user-facing warning when the configured base URL would transmit the API
    /// key and transcript content to a non-local host over plaintext HTTP. Remote
    /// HTTPS and local HTTP (loopback/private/`.local`) return `nil` so legitimate
    /// enterprise-proxy and local-provider workflows are not nagged.
    static func plaintextRemoteBaseURLWarning(
        from rawValue: String,
        provider: AIProvider = .openAI
    ) -> String? {
        let url = normalizedOpenAIBaseURL(from: rawValue, provider: provider)
        guard url.scheme?.lowercased() == "http",
              let host = url.host,
              !isLocalEndpointHost(host) else {
            return nil
        }
        return "This endpoint uses plaintext HTTP to a remote host (\(host)). "
            + "Your API key and transcript text would be sent unencrypted. Use "
            + "https:// unless this is a trusted local endpoint."
    }

    /// Warning to surface near the base-URL field for the active provider, or nil.
    var aiBaseURLPlaintextWarning: String? {
        Self.plaintextRemoteBaseURLWarning(from: openAIBaseURL, provider: aiProvider)
    }

    /// The host the configured base URL resolves to, for display near the field.
    var effectiveAIBaseURLHost: String? {
        openAIBaseURLValue.host
    }

    /// Warning when the configured Jira base URL would send Basic-auth credentials
    /// (email + API token) over plaintext HTTP to a remote host. Loopback/private/
    /// `.local` HTTP and remote HTTPS return nil. Reuses the host classifier from
    /// the AI base-URL guard (#472).
    var jiraBaseURLPlaintextWarning: String? {
        guard let url = jiraBaseURLValue,
              url.scheme?.lowercased() == "http",
              let host = url.host,
              !Self.isLocalEndpointHost(host) else {
            return nil
        }
        return "This Jira URL uses plaintext HTTP to a remote host (\(host)). "
            + "Your email and API token would be sent unencrypted. Use https:// "
            + "unless this is a trusted local server."
    }

    var preferredModelValue: String {
        Self.normalizedTranscriptionModel(preferredModel, for: aiProvider)
    }

    var normalizedLanguageHint: String? {
        normalizeOptional(languageHint)
    }

    var normalizedPrompt: String? {
        normalizeOptional(transcriptionPrompt)
    }

    var transcriptionRequest: TranscriptionRequest {
        TranscriptionRequest(
            model: preferredModelValue,
            languageHint: normalizedLanguageHint,
            prompt: normalizedPrompt,
            apiBaseURL: openAIBaseURLValue
        )
    }

    var issueExtractionModelValue: String {
        Self.normalizedIssueExtractionModel(issueExtractionModel, for: aiProvider)
    }

    var transcriptionModelChoices: [AIModelChoice] {
        Self.transcriptionModelChoices(for: aiProvider)
    }

    var issueExtractionModelChoices: [AIModelChoice] {
        Self.issueExtractionModelChoices(for: aiProvider)
    }

    var supportsIssueExtraction: Bool {
        aiProvider != .parakeetLocal
    }

    var transcriptionModelPlaceholder: String {
        switch aiProvider {
        case .openAI:
            return Self.openAITranscriptionModel
        case .openAICompatible:
            return "Provider transcription model"
        case .localCompatible:
            return "Local transcription model"
        case .parakeetLocal:
            return Self.parakeetTranscriptionModel
        }
    }

    var issueExtractionModelPlaceholder: String {
        switch aiProvider {
        case .openAI:
            return Self.openAIIssueExtractionModel
        case .openAICompatible:
            return "Provider chat model"
        case .localCompatible:
            return "Local chat model"
        case .parakeetLocal:
            return "Not available"
        }
    }

    var hasAPIKey: Bool {
        credentialIsAvailableForUserAction(
            value: trimmedAPIKey,
            persistenceState: apiKeyPersistenceState
        )
    }

    var hasUsableAIProviderCredential: Bool {
        switch aiProvider {
        case .openAI:
            return aiProviderCredentialIsAvailableForCurrentProvider(allowsLegacyOpenAICredential: true)
        case .openAICompatible:
            return aiProviderCredentialIsAvailableForCurrentProvider(allowsLegacyOpenAICredential: false)
        case .localCompatible, .parakeetLocal:
            return true
        }
    }

    var aiProviderConfigurationIsReady: Bool {
        aiProviderCompatibilityIssue == nil && hasUsableAIProviderCredential
    }

    var aiProviderCompatibilityIssue: String? {
        switch aiProvider {
        case .openAI:
            return nil
        case .openAICompatible:
            let trimmedBaseURL = openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedBaseURL.isEmpty {
                return "Choose a non-default API base URL for the OpenAI-Compatible provider."
            }
            return nil
        case .localCompatible:
            if preferredModelValue == "whisper-1" {
                return "Choose a local transcription model instead of whisper-1 for the Local-Compatible provider."
            }
            if issueExtractionModelValue == "gpt-4.1-mini" {
                return "Choose a local issue extraction model instead of gpt-4.1-mini for the Local-Compatible provider."
            }
            return nil
        case .parakeetLocal:
            if autoExtractIssues {
                return "Turn off automatic issue extraction or choose a provider with a chat completion model."
            }
            return nil
        }
    }

    func aiProviderCredentialForUserInitiatedAccess() -> String? {
        switch aiProvider {
        case .openAI:
            guard aiProviderCredentialIsAvailableForCurrentProvider(allowsLegacyOpenAICredential: true) else {
                return nil
            }

            return openAIAPIKeyForUserInitiatedAccess()
        case .openAICompatible:
            guard aiProviderCredentialIsAvailableForCurrentProvider(allowsLegacyOpenAICredential: false) else {
                return nil
            }

            return openAIAPIKeyForUserInitiatedAccess()
        case .localCompatible:
            if hasPendingSecretChanges(for: .openAI) {
                return openAIAPIKeyForUserInitiatedAccess() ?? ""
            }

            guard aiProviderCredentialIsAvailableForCurrentProvider(allowsLegacyOpenAICredential: false) else {
                return ""
            }

            return openAIAPIKeyForUserInitiatedAccess() ?? ""
        case .parakeetLocal:
            return ""
        }
    }

    var trimmedGitHubToken: String {
        githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasGitHubToken: Bool {
        !trimmedGitHubToken.isEmpty
    }

    var gitHubRepositoryDiscoveryIsReady: Bool {
        credentialIsAvailableForUserAction(
            value: trimmedGitHubToken,
            persistenceState: githubTokenPersistenceState
        )
    }



    var normalizedGitHubRepositoryOwner: String {
        githubRepositoryOwner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedGitHubRepositoryName: String {
        githubRepositoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedGitHubRepositoryID: String {
        githubRepositoryID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var gitHubConfigurationValidationIsReady: Bool {
        gitHubRepositoryDiscoveryIsReady &&
            !normalizedGitHubRepositoryOwner.isEmpty &&
            !normalizedGitHubRepositoryName.isEmpty
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
            repositoryID: normalizedGitHubRepositoryID.nilIfEmpty,
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



    var normalizedJiraBaseURL: String {
        jiraBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var normalizedJiraEmail: String {
        jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var jiraProjectDiscoveryIsReady: Bool {
        credentialIsAvailableForUserAction(
            value: normalizedJiraEmail,
            persistenceState: jiraEmailPersistenceState
        ) &&
            credentialIsAvailableForUserAction(
                value: trimmedJiraAPIToken,
                persistenceState: jiraTokenPersistenceState
            ) &&
            jiraBaseURLValue != nil
    }

    var jiraConnectionConfiguration: JiraConnectionConfiguration? {
        guard let url = jiraBaseURLValue else {
            return nil
        }

        let configuration = JiraConnectionConfiguration(
            baseURL: url,
            email: normalizedJiraEmail,
            apiToken: trimmedJiraAPIToken
        )

        return configuration.isComplete ? configuration : nil
    }

    private var jiraBaseURLValue: URL? {
        let rawValue = jiraBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        guard !rawValue.isEmpty else {
            return nil
        }

        let candidate = rawValue.contains("://") ? rawValue : "https://\(rawValue)"
        guard var components = URLComponents(string: candidate),
              let host = components.host,
              !host.isEmpty else {
            return nil
        }

        if components.scheme?.isEmpty != false {
            components.scheme = "https"
        }

        if components.path == "/" {
            components.path = ""
        }

        return components.url
    }

    var normalizedJiraProjectKey: String {
        jiraProjectKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    var normalizedJiraProjectID: String {
        jiraProjectID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedJiraIssueType: String {
        jiraIssueType.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedJiraIssueTypeID: String {
        jiraIssueTypeID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var jiraExportConfiguration: JiraExportConfiguration? {
        guard let connection = jiraConnectionConfiguration else {
            return nil
        }
        guard !normalizedJiraProjectKey.isEmpty,
              !(normalizedJiraIssueTypeID.isEmpty && normalizedJiraIssueType.isEmpty) else {
            return nil
        }

        let configuration = JiraExportConfiguration(
            baseURL: connection.baseURL,
            email: connection.email,
            apiToken: connection.apiToken,
            projectID: normalizedJiraProjectID.nilIfEmpty,
            projectKey: normalizedJiraProjectKey,
            issueTypeID: normalizedJiraIssueTypeID,
            issueTypeName: normalizedJiraIssueType
        )

        return configuration.isComplete ? configuration : nil
    }

    private let defaults: UserDefaults
    private let secretStore: KeychainSecretStoring
    private let recordingPreferences: RecordingPreferencesStore
    private let trackerExportSettings: TrackerExportSettingsStore
    private let launchAtLoginService: any LaunchAtLoginControlling
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let legacyDefaultsDomains: [String]
    private var hasLoaded = false
    private var isSynchronizingHotkeys = false
    private var isSynchronizingLaunchAtLogin = false
    private var sessionOnlySecrets: [SecretSlot: String] = [:]
    private var committedSecrets: [SecretSlot: String] = [:]
    private var committedSecretStates: [SecretSlot: APIKeyPersistenceState] = [:]

    init(
        defaults: UserDefaults = .standard,
        keychainService: KeychainServicing = KeychainService(),
        launchAtLoginService: any LaunchAtLoginControlling = SystemLaunchAtLoginService(),
        legacyDefaultsDomains: [String]? = nil
    ) {
        self.defaults = defaults
        self.recordingPreferences = RecordingPreferencesStore(defaults: defaults)
        self.trackerExportSettings = TrackerExportSettingsStore(defaults: defaults)
        self.secretStore = KeychainSecretStore(keychainService: keychainService)
        self.launchAtLoginService = launchAtLoginService
        if let legacyDefaultsDomains {
            self.legacyDefaultsDomains = legacyDefaultsDomains
        } else if defaults === UserDefaults.standard {
            self.legacyDefaultsDomains = Self.defaultLegacyDefaultsDomains
        } else {
            self.legacyDefaultsDomains = []
        }

        load()
        hasLoaded = true
    }

    private static func transcriptionModelChoices(for provider: AIProvider) -> [AIModelChoice] {
        switch provider {
        case .openAI:
            return openAITranscriptionModelChoices
        case .parakeetLocal:
            return parakeetTranscriptionModelChoices
        case .openAICompatible, .localCompatible:
            return []
        }
    }

    private static func issueExtractionModelChoices(for provider: AIProvider) -> [AIModelChoice] {
        switch provider {
        case .openAI:
            return openAIIssueExtractionModelChoices
        case .openAICompatible, .localCompatible, .parakeetLocal:
            return []
        }
    }

    private static func normalizedTranscriptionModel(_ rawValue: String, for provider: AIProvider) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch provider {
        case .openAI:
            let allowedModels = Set(openAITranscriptionModelChoices.map(\.id))
            return allowedModels.contains(value) ? value : openAITranscriptionModel
        case .parakeetLocal:
            return parakeetTranscriptionModel
        case .openAICompatible, .localCompatible:
            return value.isEmpty ? openAITranscriptionModel : value
        }
    }

    private static func normalizedIssueExtractionModel(_ rawValue: String, for provider: AIProvider) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch provider {
        case .openAI:
            let allowedModels = Set(openAIIssueExtractionModelChoices.map(\.id))
            return allowedModels.contains(value) ? value : openAIIssueExtractionModel
        case .openAICompatible, .localCompatible, .parakeetLocal:
            return value.isEmpty ? openAIIssueExtractionModel : value
        }
    }

    private func normalizeTranscriptionModelForCurrentProvider(persist: Bool) {
        let normalizedModel = Self.normalizedTranscriptionModel(preferredModel, for: aiProvider)
        guard normalizedModel != preferredModel else { return }

        preferredModel = normalizedModel
        if persist {
            defaults.set(normalizedModel, forKey: Keys.preferredModel)
        }
    }

    private func normalizeIssueExtractionModelForCurrentProvider(persist: Bool) {
        let normalizedModel = Self.normalizedIssueExtractionModel(issueExtractionModel, for: aiProvider)
        guard normalizedModel != issueExtractionModel else { return }

        issueExtractionModel = normalizedModel
        if persist {
            defaults.set(normalizedModel, forKey: Keys.issueExtractionModel)
        }
    }

    private func normalizeIssueExtractionAvailabilityForCurrentProvider(persist: Bool) {
        guard !supportsIssueExtraction, autoExtractIssues else { return }

        autoExtractIssues = false
        if persist {
            defaults.set(false, forKey: Keys.autoExtractIssues)
        }
    }

    func refreshSecretsForUserInitiatedAccess() {
        logger.debug("refresh_all_secrets", "Refreshing stored secrets after a user-initiated action.")
        prepareSecretsForUserInitiatedAccess(
            slots: Array(SecretSlot.allCases),
            includeLegacyServices: true
        )
    }

    func refreshOpenAISecretForUserInitiatedAccess() {
        logger.debug("refresh_openai_secret", "Refreshing the OpenAI API key after a user-initiated action.")
        prepareSecretsForUserInitiatedAccess(slots: [.openAI], includeLegacyServices: true)
    }

    func openAIAPIKeyForUserInitiatedAccess() -> String? {
        let pendingValue = hasPendingSecretChanges(for: .openAI) ? trimmedAPIKey : ""
        prepareSecretsForUserInitiatedAccess(slots: [.openAI], includeLegacyServices: true)

        if !pendingValue.isEmpty {
            apiKey = ""
            return pendingValue
        }

        let secret = loadSecret(
            for: .openAI,
            allowInteraction: true,
            includeLegacyServices: true
        )
        setPersistenceState(secret.state, for: .openAI)

        return secret.value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    func refreshExportSecretsForUserInitiatedAccess() {
        logger.debug("refresh_export_secrets", "Refreshing export credentials after a user-initiated action.")
        prepareSecretsForUserInitiatedAccess(
            slots: [.github, .jiraEmail, .jira],
            includeLegacyServices: true
        )
    }

    func removeAPIKey() {
        apiKey = ""
        apiKeyPersistenceState = persistSecret(apiKey, for: .openAI)
        logger.info("remove_openai_key", "The OpenAI API key was removed from local storage.")
    }

    func removeGitHubToken() {
        githubToken = ""
        githubTokenPersistenceState = persistSecret(githubToken, for: .github)
        logger.info("remove_github_token", "The GitHub export token was removed from local storage.")
    }

    func removeJiraAPIToken() {
        jiraAPIToken = ""
        jiraTokenPersistenceState = persistSecret(jiraAPIToken, for: .jira)
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
        aiProvider = AIProvider(rawValue: stringValue(forKey: Keys.aiProvider) ?? "") ?? .openAI
        openAIBaseURL = stringValue(forKey: Keys.openAIBaseURL) ?? ""
        languageHint = stringValue(forKey: Keys.languageHint) ?? Self.defaultLanguageHint
        transcriptionPrompt = stringValue(forKey: Keys.transcriptionPrompt) ?? ""
        issueExtractionModel = stringValue(
            forKey: Keys.issueExtractionModel,
            legacyKeys: [Keys.legacyIssueExtractionModel]
        )
            ?? Self.openAIIssueExtractionModel
        normalizeTranscriptionModelForCurrentProvider(persist: true)
        normalizeIssueExtractionModelForCurrentProvider(persist: true)

        autoCopyTranscript = boolValue(forKey: Keys.autoCopyTranscript) ?? true
        autoSaveTranscript = boolValue(forKey: Keys.autoSaveTranscript) ?? true
        autoExtractIssues = boolValue(forKey: Keys.autoExtractIssues) ?? false
        normalizeIssueExtractionAvailabilityForCurrentProvider(persist: true)
        systemAudioCaptureEnabled = boolValue(forKey: RecordingPreferencesStore.Keys.systemAudioCaptureEnabled) ?? false
        let storedAudioSource = stringValue(forKey: RecordingPreferencesStore.Keys.recordingAudioSource)
        let parsedAudioSource = storedAudioSource
            .flatMap(RecordingAudioSource.init(rawValue:))
            ?? .microphone
        let normalizedAudioSource = recordingPreferences.normalizedRecordingAudioSource(
            parsedAudioSource,
            systemAudioCaptureEnabled: systemAudioCaptureEnabled
        )
        recordingAudioSource = normalizedAudioSource
        if normalizedAudioSource != parsedAudioSource {
            // hasLoaded is still false here, so the property's didSet does not
            // persist — write the normalized value back explicitly, as before.
            recordingPreferences.persist(recordingAudioSource: normalizedAudioSource)
        }
        hasAcceptedSystemAudioRecordingConsent = boolValue(
            forKey: RecordingPreferencesStore.Keys.hasAcceptedSystemAudioRecordingConsent
        ) ?? false
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

        githubRepositoryOwner = stringValue(forKey: TrackerExportSettingsStore.Keys.githubRepositoryOwner) ?? ""
        githubRepositoryName = stringValue(forKey: TrackerExportSettingsStore.Keys.githubRepositoryName) ?? ""
        githubRepositoryID = stringValue(forKey: TrackerExportSettingsStore.Keys.githubRepositoryID) ?? ""
        githubDefaultLabels = stringValue(forKey: TrackerExportSettingsStore.Keys.githubDefaultLabels) ?? ""

        jiraBaseURL = stringValue(forKey: TrackerExportSettingsStore.Keys.jiraBaseURL) ?? ""
        jiraProjectID = stringValue(forKey: TrackerExportSettingsStore.Keys.jiraProjectID) ?? ""
        jiraProjectKey = stringValue(forKey: TrackerExportSettingsStore.Keys.jiraProjectKey) ?? ""
        jiraIssueTypeID = stringValue(forKey: TrackerExportSettingsStore.Keys.jiraIssueTypeID) ?? ""
        jiraIssueType = stringValue(forKey: TrackerExportSettingsStore.Keys.jiraIssueType) ?? ""
        migrateLegacyPlaintextJiraEmailIfNeeded()

        debugMode = boolValue(forKey: Keys.debugMode) ?? false
        operationalTelemetryEnabled = boolValue(forKey: Keys.operationalTelemetryEnabled) ?? true
        autoShowChangelogOnUpdate = boolValue(forKey: Keys.autoShowChangelogOnUpdate) ?? true
        suppressSystemAudioExplainer = boolValue(forKey: RecordingPreferencesStore.Keys.suppressSystemAudioExplainer) ?? false
        migrateLegacyBuiltInHotkeysIfNeeded()
        normalizeLoadedHotkeyConflicts()
        BugNarratorDiagnostics.setDebugModeEnabled(debugMode)
        logger.info(
            "settings_loaded",
            "Settings finished loading.",
            metadata: [
                "debug_mode": debugMode ? "enabled" : "disabled",
                "recording_audio_source": recordingAudioSource.diagnosticsValue,
                "system_audio_capture": systemAudioCaptureEnabled ? "enabled" : "disabled",
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
                apiKey = secret.state == .sessionOnly ? secret.value : ""
                setPersistenceState(secret.state, for: slot)
            case .github:
                githubToken = secret.value
                setPersistenceState(secret.state, for: slot)
            case .jiraEmail:
                jiraEmail = secret.value
                setPersistenceState(secret.state, for: slot)
            case .jira:
                jiraAPIToken = secret.value
                setPersistenceState(secret.state, for: slot)
            }

            committedSecrets[slot] = slot == .openAI && secret.state == .keychain ? "" : secret.value
            committedSecretStates[slot] = secret.state
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
            conflictingHotkeyAction = conflictingAction
            setShortcut(previousShortcut, for: changedAction)
            return
        }

        hotkeyConflictMessage = nil
        conflictingHotkeyAction = nil
        persistHotkey(changedShortcut, key: storageKey(for: changedAction))
    }

    /// Clears the binding for the named action, resolving a reported conflict.
    func clearHotkey(for action: HotkeyAction) {
        setShortcut(.disabled, for: action)
        hotkeyConflictMessage = nil
        conflictingHotkeyAction = nil
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
            openAtStartupStatusMessage = launchAtLoginFailureMessage(status: status, error: error)
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

    private func launchAtLoginFailureMessage(status: LaunchAtLoginStatus, error: Error) -> String {
        let errorDetails = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !errorDetails.isEmpty else {
            return status.message ?? "BugNarrator couldn't update the Open at Startup setting."
        }

        if let statusMessage = status.message {
            return "\(statusMessage) Details: \(errorDetails)"
        }

        return "BugNarrator couldn't update the Open at Startup setting. \(errorDetails)"
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
        case .requiresApproval, .notFound, .unavailable:
            openAtStartupStatusTone = .warning
        }
    }

    /// Best-effort removal of a secret from a slot's legacy service names.
    /// Missing items are not an error (KeychainService treats not-found as
    /// success); a genuine failure is logged but does not block the primary
    /// operation, since the canonical service-name delete is what matters.
    private func deleteLegacySecrets(for slot: SecretSlot) {
        for failure in secretStore.deleteLegacyValues(for: slot) {
            logger.warning(
                "secret_legacy_clear_failed",
                "A legacy secure value could not be removed from Keychain.",
                metadata: [
                    "slot": slot.redactionSafeName,
                    "error": failure.redactedDetail
                ]
            )
        }
    }

    @discardableResult
    private func persistSecret(_ value: String, for slot: SecretSlot) -> APIKeyPersistenceState {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedValue.isEmpty {
            sessionOnlySecrets.removeValue(forKey: slot)
            do {
                try secretStore.deleteCanonicalValue(for: slot)
            } catch {
                // KeychainService maps "item not found" to success, so any thrown
                // error means the secret is still resident. Surface it instead of
                // reporting the credential as cleared — otherwise the UI/state
                // would diverge from what is actually in the Keychain.
                logger.warning(
                    "secret_clear_failed",
                    "A secure value could not be removed from Keychain.",
                    metadata: [
                        "slot": slot.redactionSafeName,
                        "error": KeychainSecretStore.redactedErrorDetail(error)
                    ]
                )
                committedSecretStates[slot] = .keychain
                return .keychain
            }
            deleteLegacySecrets(for: slot)
            logger.info(
                "secret_cleared",
                "A secure value was cleared from persistent storage.",
                metadata: ["slot": slot.redactionSafeName]
            )
            if slot == .openAI {
                defaults.removeObject(forKey: Keys.aiProviderCredentialProvider)
            }
            committedSecrets[slot] = ""
            committedSecretStates[slot] = .empty
            return .empty
        }

        do {
            try secretStore.saveCanonicalValue(trimmedValue, for: slot)
            deleteLegacySecrets(for: slot)
            sessionOnlySecrets.removeValue(forKey: slot)
            logger.info(
                "secret_persisted",
                "A secure value was saved to Keychain.",
                metadata: ["slot": slot.redactionSafeName]
            )
            if slot == .openAI {
                defaults.set(aiProvider.rawValue, forKey: Keys.aiProviderCredentialProvider)
            }
            committedSecrets[slot] = slot == .openAI ? "" : trimmedValue
            committedSecretStates[slot] = .keychain
            return .keychain
        } catch {
            sessionOnlySecrets[slot] = trimmedValue
            logger.warning(
                "secret_persisted_in_memory",
                "Keychain storage was unavailable, so a secure value is only kept in memory for this run.",
                metadata: ["slot": slot.redactionSafeName]
            )
            if slot == .openAI {
                defaults.set(aiProvider.rawValue, forKey: Keys.aiProviderCredentialProvider)
            }
            committedSecrets[slot] = trimmedValue
            committedSecretStates[slot] = .sessionOnly
            return .sessionOnly
        }
    }

    private func loadSecret(
        for slot: SecretSlot,
        allowInteraction: Bool,
        includeLegacyServices: Bool
    ) -> (value: String, state: APIKeyPersistenceState) {
        do {
            if let keychainValue = try secretStore.readCanonicalValue(
                for: slot,
                allowInteraction: allowInteraction
            ),
               !keychainValue.isEmpty {
                return (keychainValue, .keychain)
            }

            if includeLegacyServices,
               let legacyValue = try secretStore.readFirstLegacyValue(
                for: slot,
                allowInteraction: allowInteraction
               ) {
                _ = persistSecret(legacyValue, for: slot)
                return (legacyValue, .keychain)
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



    private func prepareSecretsForUserInitiatedAccess(
        slots: [SecretSlot],
        includeLegacyServices: Bool
    ) {
        let pendingSlots = slots.filter(hasPendingSecretChanges)
        for slot in pendingSlots {
            let state = persistSecret(currentSecretValue(for: slot), for: slot)
            setPersistenceState(state, for: slot)
            if slot == .openAI, state == .keychain {
                apiKey = ""
            }
        }

        let reloadableSlots = slots.filter {
            !hasPendingSecretChanges(for: $0) && persistenceState(for: $0) == .keychainLocked
        }

        if !reloadableSlots.isEmpty {
            reloadSecrets(
                slots: reloadableSlots,
                allowInteraction: true,
                includeLegacyServices: includeLegacyServices
            )
        }
    }

    private func secretDidChange(_ slot: SecretSlot) {
        let currentValue = currentSecretValue(for: slot).trimmingCharacters(in: .whitespacesAndNewlines)
        let committedValue = (committedSecrets[slot] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let committedState = committedSecretStates[slot] ?? .empty

        if currentValue == committedValue {
            setPersistenceState(committedState, for: slot)
            return
        }

        if currentValue.isEmpty && committedState == .empty {
            setPersistenceState(.empty, for: slot)
            return
        }

        setPersistenceState(.pendingSave, for: slot)
    }

    private func hasPendingSecretChanges(for slot: SecretSlot) -> Bool {
        persistenceState(for: slot) == .pendingSave
    }

    private func credentialIsAvailableForUserAction(
        value: String,
        persistenceState: APIKeyPersistenceState
    ) -> Bool {
        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        switch persistenceState {
        case .keychain, .keychainLocked:
            return true
        case .empty, .sessionOnly, .pendingSave:
            return false
        }
    }

    private var savedAIProviderCredentialProvider: AIProvider? {
        guard let rawValue = defaults.string(forKey: Keys.aiProviderCredentialProvider) else {
            return nil
        }

        return AIProvider(rawValue: rawValue)
    }

    private func aiProviderCredentialIsAvailableForCurrentProvider(
        allowsLegacyOpenAICredential: Bool
    ) -> Bool {
        if hasPendingSecretChanges(for: .openAI) {
            return !trimmedAPIKey.isEmpty
        }

        guard credentialIsAvailableForUserAction(
            value: trimmedAPIKey,
            persistenceState: apiKeyPersistenceState
        ) else {
            return false
        }

        return aiProviderCredentialMatchesCurrentProvider(
            allowsLegacyOpenAICredential: allowsLegacyOpenAICredential
        )
    }

    private func aiProviderCredentialMatchesCurrentProvider(
        allowsLegacyOpenAICredential: Bool
    ) -> Bool {
        guard let savedProvider = savedAIProviderCredentialProvider else {
            // Legacy credential with no provider tag. Accept it for any
            // provider that uses the OpenAI credential slot and tag it
            // so future checks are fast.
            let credentialExists = apiKeyPersistenceState == .keychain || apiKeyPersistenceState == .keychainLocked
            if credentialExists && aiProvider.requiresAPIKey {
                defaults.set(aiProvider.rawValue, forKey: Keys.aiProviderCredentialProvider)
                return true
            }
            return allowsLegacyOpenAICredential && aiProvider == .openAI
        }

        return savedProvider == aiProvider
    }

    private func currentSecretValue(for slot: SecretSlot) -> String {
        switch slot {
        case .openAI:
            return apiKey
        case .github:
            return githubToken
        case .jiraEmail:
            return jiraEmail
        case .jira:
            return jiraAPIToken
        }
    }

    private func persistenceState(for slot: SecretSlot) -> APIKeyPersistenceState {
        switch slot {
        case .openAI:
            return apiKeyPersistenceState
        case .github:
            return githubTokenPersistenceState
        case .jiraEmail:
            return jiraEmailPersistenceState
        case .jira:
            return jiraTokenPersistenceState
        }
    }

    private func setPersistenceState(_ state: APIKeyPersistenceState, for slot: SecretSlot) {
        switch slot {
        case .openAI:
            guard apiKeyPersistenceState != state else { return }
            apiKeyPersistenceState = state
        case .github:
            guard githubTokenPersistenceState != state else { return }
            githubTokenPersistenceState = state
        case .jiraEmail:
            guard jiraEmailPersistenceState != state else { return }
            jiraEmailPersistenceState = state
        case .jira:
            guard jiraTokenPersistenceState != state else { return }
            jiraTokenPersistenceState = state
        }
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

private enum Keys {
    static let aiProvider = "settings.aiProvider"
    static let aiProviderCredentialProvider = "settings.aiProviderCredentialProvider"
    static let preferredModel = "settings.preferredModel"
    static let openAIBaseURL = "settings.openAIBaseURL"
    static let languageHint = "settings.languageHint"
    static let transcriptionPrompt = "settings.transcriptionPrompt"
    static let issueExtractionModel = "settings.issueExtractionModel"
    static let legacyIssueExtractionModel = "settings.reviewProcessingModel"
    static let autoCopyTranscript = "settings.autoCopyTranscript"
    static let autoSaveTranscript = "settings.autoSaveTranscript"
    static let autoExtractIssues = "settings.autoExtractIssues"
    // Recording-audio preference keys live on RecordingPreferencesStore.Keys (#429).
    static let startRecordingHotkeyShortcut = "settings.startRecordingHotkeyShortcut"
    static let legacyRecordingHotkeyShortcut = "settings.hotkeyShortcut"
    static let legacyStartRecordingHotkeyShortcut = "settings.recordingHotkeyShortcut"
    static let stopRecordingHotkeyShortcut = "settings.stopRecordingHotkeyShortcut"
    static let markerHotkeyShortcut = "settings.markerHotkeyShortcut"
    static let screenshotHotkeyShortcut = "settings.screenshotHotkeyShortcut"
    static let didMigrateLegacyBuiltInHotkeys = "settings.didMigrateLegacyBuiltInHotkeys"
    // GitHub/Jira tracker export config keys live on TrackerExportSettingsStore.Keys (#429).
    static let jiraEmail = "settings.jiraEmail"
    static let debugMode = "settings.debugMode"
    static let operationalTelemetryEnabled = OperationalTelemetryRecorder.enabledDefaultsKey
    static let autoShowChangelogOnUpdate = "settings.autoShowChangelogOnUpdate"
    static let lastShownChangelogVersion = "settings.lastShownChangelogVersion"
}

enum APIKeyPersistenceState: Equatable {
    case empty
    case keychain
    case keychainLocked
    case sessionOnly
    case pendingSave
}

enum SettingsCalloutTone: Equatable {
    case secondary
    case warning
    case error
}
