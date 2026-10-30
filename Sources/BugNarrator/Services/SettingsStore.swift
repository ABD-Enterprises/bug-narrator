import Combine
import Darwin
import Foundation

struct AIModelChoice: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
}

enum LocalProviderReachability: Equatable {
    case unknown
    case reachable
    case unreachable
}

final class SettingsStore: ObservableObject {
    static let defaultLegacyDefaultsDomains = [
        "com.abdenterprises.sessionmic"
    ]

    static let openAITranscriptionModel = "whisper-1"
    private static let defaultLanguageHint = "en"
    static let openAIIssueExtractionModel = "gpt-4.1-mini"
    static let localTranscriptionRunCommand = "./bugnarrator-transcription --preload"

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
    @Published private(set) var localProviderReachability: LocalProviderReachability = .unknown

    @Published var openAIBaseURL: String = "" {
        didSet {
            guard hasLoaded else { return }
            defaults.set(openAIBaseURL, forKey: Keys.openAIBaseURL)
            refreshLocalProviderReachabilityIfNeeded()
        }
    }

    @Published var aiProvider: AIProvider = .parakeetLocal {
        didSet {
            guard hasLoaded else { return }
            defaults.set(aiProvider.rawValue, forKey: Keys.aiProvider)
            normalizeTranscriptionModelForCurrentProvider(persist: true)
            normalizeIssueExtractionModelForCurrentProvider(persist: true)
            normalizeIssueExtractionAvailabilityForCurrentProvider(persist: true)
            refreshLocalProviderReachabilityIfNeeded()
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

    /// Default-off since #952. Copying a full transcript to the system
    /// pasteboard on every save is a privacy-adjacent side effect — clipboard
    /// managers persist it and an accidental paste leaks it — so it is opt-in
    /// rather than opt-out. An explicit choice is stored and still honored, so
    /// only users who never touched the toggle see the new default.
    /// Off by default (#950). Issue extraction used to base64-embed up to four
    /// screenshots into the provider request unconditionally, while the README
    /// listed screenshots under "Data that stays local on your Mac". Sending a
    /// picture of the user's screen to a third party is not a default anyone
    /// agreed to, so it is opt-in.
    @Published var uploadScreenshotsForExtraction: Bool = false {
        didSet {
            guard hasLoaded else { return }
            defaults.set(uploadScreenshotsForExtraction, forKey: Keys.uploadScreenshotsForExtraction)
        }
    }

    @Published var autoCopyTranscript: Bool = false {
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

    /// Whether the one-time "extract issues from this session?" offer has
    /// already been made (#912).
    ///
    /// `autoExtractIssues` deliberately stays off by default — turning it on
    /// would spend the user's provider credit on every session without asking.
    /// Instead the offer is made once, after a transcript exists, so the
    /// differentiating feature is discoverable without a surprise charge.
    @Published private(set) var hasOfferedIssueExtraction: Bool = false

    /// Records that the offer has been shown. Declining is permanent in the
    /// sense that the user is never asked again; they can still enable
    /// extraction in Settings at any time.
    func markIssueExtractionOffered() {
        guard !hasOfferedIssueExtraction else {
            return
        }

        hasOfferedIssueExtraction = true
        defaults.set(true, forKey: Keys.hasOfferedIssueExtraction)
    }

    /// Whether the session-library offer banner should be visible (#912).
    ///
    /// Adds the "a transcript already exists" condition to
    /// `shouldOfferIssueExtraction`, so the offer follows real work the user
    /// can see rather than greeting an empty library.
    static func shouldShowIssueExtractionOfferBanner(
        autoExtractIssues: Bool,
        hasOffered: Bool,
        supportsIssueExtraction: Bool,
        hasAnySession: Bool
    ) -> Bool {
        guard hasAnySession else { return false }
        return shouldOfferIssueExtraction(
            autoExtractIssues: autoExtractIssues,
            hasOffered: hasOffered,
            supportsIssueExtraction: supportsIssueExtraction
        )
    }

    /// Pure decision for whether to surface the one-time offer (#912).
    ///
    /// Deliberately keyed off `supportsIssueExtraction` rather than credential
    /// readiness: `hasUsableAIProviderCredential` returns `true`
    /// unconditionally for local providers, and Local (Parakeet) is
    /// transcription-only, so keying off the credential would offer extraction
    /// on a provider that cannot perform it.
    static func shouldOfferIssueExtraction(
        autoExtractIssues: Bool,
        hasOffered: Bool,
        supportsIssueExtraction: Bool
    ) -> Bool {
        guard supportsIssueExtraction else { return false }
        guard !autoExtractIssues else { return false }
        return !hasOffered
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

    /// Whether the first-run welcome tour has already been shown, completed, or
    /// skipped (#357). Skipping is durable: it sets the same flag completion
    /// does, so a user who dismissed the tour is not re-prompted every launch.
    var hasCompletedFirstRunOnboarding: Bool {
        boolValue(forKey: Keys.hasCompletedFirstRunOnboarding) ?? false
    }

    func markFirstRunOnboardingCompleted() {
        defaults.set(true, forKey: Keys.hasCompletedFirstRunOnboarding)
    }

    /// True when at least one of the three capture actions has a shortcut bound.
    ///
    /// Reads the live assignments rather than a stored flag so it stays honest
    /// after `migrateLegacyBuiltInHotkeysIfNeeded` strips the 1.0.11 built-ins.
    var hasAnyCaptureHotkeyAssigned: Bool {
        hotkeyAssignments.contains { $0.shortcut.isEnabled }
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

    static func isHealthyLocalProvider(data: Data?, response: URLResponse?) -> Bool {
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              let data,
              let health = try? JSONDecoder().decode(LocalProviderHealth.self, from: data) else {
            return false
        }
        return health.status == "ok"
    }

    private struct LocalProviderHealth: Decodable {
        let status: String
        let model_loaded: Bool
    }

    /// Whether `host` denotes a loopback / private / link-local endpoint.
    /// Plaintext HTTP to such a host is acceptable because the traffic stays on
    /// the machine or the trusted local network; plaintext HTTP to any other
    /// host would send the API key and transcript text over the public
    /// internet unencrypted.
    ///
    /// A `.local` name and a single-label name are deliberately not trusted.
    /// Both are resolved over mDNS, which any device on the local network can
    /// answer, so a name that looks local can point anywhere — and ATS offers
    /// no protection for them either. A local server is addressed by its IP
    /// address instead.
    static func isLocalEndpointHost(_ host: String) -> Bool {
        let lowered = withoutIPv6Brackets(host.lowercased())

        if isReservedLocalhostName(lowered) { return true }
        if isIPv6LocalEndpointHost(lowered) { return true }

        guard let octets = canonicalDottedQuad(lowered) else { return false }
        if octets == (0, 0, 0, 0) { return true }  // this machine
        return isTrustedIPv4(octets.0, octets.1)
    }

    /// The host without the brackets an IPv6 literal is written in.
    ///
    /// Only an IPv6 literal carries brackets. `[localhost]` is not one, and
    /// reading it as `localhost` would make the app trust a name it cannot
    /// check - the brackets are part of the host, not decoration.
    private static func withoutIPv6Brackets(_ host: String) -> String {
        guard host.hasPrefix("["), host.hasSuffix("]"), host.contains(":") else { return host }
        return String(host.dropFirst().dropLast())
    }

    /// The name `host` refers to, with one trailing dot removed.
    ///
    /// A trailing dot makes a name absolute rather than different: a resolver
    /// looks up the same name either way, so the two have to be classified the
    /// same way. It does not rescue an address literal — `127.0.0.1.` is not
    /// the address any more, it is a name the app cannot check, and a
    /// resolver does not answer it at all.
    private static func nameForm(of host: String) -> String {
        host.hasSuffix(".") ? String(host.dropLast()) : host
    }

    /// Whether `host` is one of the names the standards reserve for the
    /// loopback: `localhost` itself, and a name under it.
    ///
    /// Every label has to be there. A name that only looks like a reserved one
    /// — a leading dot, an empty label — is not one of them. A trailing dot
    /// is: it makes the name absolute rather than different, and a resolver
    /// answers a reserved name with the loopback address without ever putting
    /// the question to the network (RFC 6761).
    private static func isReservedLocalhostName(_ host: String) -> Bool {
        let name = nameForm(of: host)
        if name == "localhost" { return true }

        // The empty labels are the point: a name that starts or ends with a
        // dot leaves one behind, and ".localhost" is not the reserved name.
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count > 1 else { return false }
        guard labels.last.map(String.init) == "localhost" else { return false }
        return labels.dropLast().allSatisfy { !$0.isEmpty }
    }

    /// Whether the four octets are in a range that stays on the machine or the
    /// trusted local network.
    private static func isTrustedIPv4(_ first: UInt8, _ second: UInt8) -> Bool {
        switch (first, second) {
        case (127, _): return true        // loopback 127.0.0.0/8
        case (10, _): return true         // private 10.0.0.0/8
        case (192, 168): return true      // private 192.168.0.0/16
        case (169, 254): return true      // link-local 169.254.0.0/16
        case (172, 16...31): return true  // private 172.16.0.0/12
        default: return false
        }
    }

    /// Whether `host` is an IPv6 address that stays on the machine or the
    /// trusted local network.
    ///
    /// `::1` is the loopback, `fe80::/10` is the link-local range, and
    /// `::ffff:127.0.0.1` is the loopback written as an IPv4-mapped IPv6
    /// address. Comparing the strings would miss every other spelling of them
    /// — `0:0:0:0:0:0:0:1` is the same address as `::1` — so the address is
    /// parsed instead.
    private static func isIPv6LocalEndpointHost(_ host: String) -> Bool {
        // A zone id (`fe80::1%en0`) names the interface, not the address, so
        // it is removed before the address is parsed. Darwin's parser accepts
        // it and writes the interface index into the address bytes, which
        // would corrupt the comparison.
        let addressText = host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host

        // An address that carries an IPv4 address in its last group has to
        // spell that address the way an address is written too. The mapped
        // form is another way to write the same address, and a leading zero
        // in it is the same ambiguity the canonical rule exists to remove.
        if let embedded = embeddedIPv4Text(addressText), canonicalDottedQuad(embedded) == nil {
            return false
        }

        var address = in6_addr()
        guard inet_pton(AF_INET6, addressText, &address) == 1 else { return false }

        let bytes = withUnsafeBytes(of: &address) { Array($0) }
        // :: — the unspecified address, the IPv6 spelling of 0.0.0.0. A
        // connection to it reaches the loopback interface, the same way a
        // connection to 0.0.0.0 does, so the two spellings of "this machine"
        // have to be trusted together.
        if bytes.allSatisfy({ $0 == 0 }) { return true }
        // ::1 — the loopback.
        if bytes == [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1] { return true }
        // fe80::/10 — the link-local range.
        if bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80 { return true }
        // ::ffff:a.b.c.d — an IPv4 address written as an IPv6 one.
        if bytes[0..<10].allSatisfy({ $0 == 0 }) && bytes[10] == 0xff && bytes[11] == 0xff {
            // ::ffff:0.0.0.0 is 0.0.0.0 written as an IPv6 address, so it is
            // this machine the same way 0.0.0.0 is.
            if bytes[12] == 0 && bytes[13] == 0 && bytes[14] == 0 && bytes[15] == 0 { return true }
            return isTrustedIPv4(bytes[12], bytes[13])
        }
        return false
    }

    /// The IPv4 address an IPv6 literal carries in its last group, if it has
    /// one.
    private static func embeddedIPv4Text(_ address: String) -> String? {
        guard address.contains(".") else { return nil }
        let tail = address.split(separator: ":").last.map(String.init) ?? ""
        return tail.contains(".") ? tail : nil
    }

    /// The four octets of `host`, when it is an IPv4 literal written the way an
    /// address is written.
    ///
    /// The spelling has to be canonical, because the app and the network have to
    /// read the host the same way. A leading zero (`010.0.0.1`) is a different
    /// octet to a resolver that reads it as octal — eight, not ten — and a
    /// trailing or leading dot (`127.0.0.1.`) turns the host into an absolute
    /// DNS name that a resolver anywhere on the network can answer. The app
    /// cannot know which reading it will be handed, so it trusts none of them.
    private static func canonicalDottedQuad(_ host: String) -> (UInt8, UInt8, UInt8, UInt8)? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }

        var octets: [UInt8] = []
        octets.reserveCapacity(4)
        for part in parts {
            guard !part.isEmpty,
                  part.count <= 3,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  // A leading zero is another spelling of the same octet, not
                  // the octet itself.
                  !(part.count > 1 && part.hasPrefix("0")),
                  let value = UInt8(part)
            else {
                return nil
            }
            octets.append(value)
        }
        return (octets[0], octets[1], octets[2], octets[3])
    }

    /// Whether `host` is an address the app parsed and found to be somewhere
    /// else — a public address, written the way an address is written.
    ///
    /// A host in another notation (`134744072`, `127.1`) is not parseable, so
    /// it is neither a local nor a public address as far as the app is
    /// concerned: the app cannot say where it points.
    static func isPublicAddress(_ host: String) -> Bool {
        let lowered = withoutIPv6Brackets(host.lowercased())

        guard let octets = canonicalDottedQuad(lowered) else { return false }
        // The unspecified, multicast and broadcast addresses are not a host on
        // the public internet: the 0.0.0.0/8 range means "this network" rather
        // than a destination (RFC 1122), and the other two are not addressed to
        // one host. Calling them remote would be a claim the app cannot make.
        if octets.0 == 0 { return false }
        if (224...239).contains(octets.0) { return false }
        if octets == (255, 255, 255, 255) { return false }
        return !isLocalEndpointHost(host)
    }

    /// Whether `host` is a name that resolves over mDNS rather than an address
    /// the app can check: a `.local` name, or a single-label name such as
    /// `lmstudio`. Any device on the local network can answer for such a name,
    /// so it is not a trusted endpoint even though it looks local.
    static func isUnqualifiedLocalName(_ host: String) -> Bool {
        let lowered = withoutIPv6Brackets(host.lowercased())
        // A trailing dot makes the name absolute rather than different: a
        // resolver answers the same name either way, so the two are the same
        // host and have to be classified the same way.
        let name = nameForm(of: lowered)

        guard !name.isEmpty else { return false }
        // An IPv4 literal in another notation — `134744072`, `0x7f000001` — is
        // an address, not a name anybody can claim for it.
        if isNumericAddressLiteral(name) { return false }
        // `localhost` is reserved and always resolves to loopback.
        if isReservedLocalhostName(name) { return false }
        if name.hasSuffix(".local") { return true }
        return !name.contains(".") && !name.contains(":")
    }

    /// Whether `host` is a number written in a notation other than the dotted
    /// quad: decimal (`134744072`) or hexadecimal (`0x7f000001`).
    static func isNumericAddressLiteral(_ host: String) -> Bool {
        guard !host.isEmpty else { return false }
        // Only ASCII digits count. A character is a number in more than one
        // script, and a name written in one of them is a name, not an
        // address.
        if host.allSatisfy({ $0.isASCII && $0.isNumber }) { return true }
        guard host.hasPrefix("0x") || host.hasPrefix("0X") else { return false }
        let digits = host.dropFirst(2)
        return !digits.isEmpty && digits.allSatisfy({ $0.isASCII && $0.isHexDigit })
    }

    /// Whether the settings screen has to render the compatibility issue.
    ///
    /// For a refused plaintext endpoint the warning next to the base URL field
    /// and the compatibility issue are the same sentence, so the screen shows
    /// it once. A different compatibility issue - a missing base URL, a model
    /// the provider does not offer - is a different sentence and is shown.
    var shouldRenderCompatibilityIssue: Bool {
        guard let compatibilityIssue = aiProviderCompatibilityIssue else { return false }
        return compatibilityIssue != aiBaseURLPlaintextWarning
    }

    /// The message for an endpoint that is refused over plaintext HTTP because
    /// its name is answered by the network rather than by the app. It names the
    /// fix, because the user is looking at a field they believe is correct.
    static func unqualifiedLocalHostPlaintextMessage(host: String, secret: String) -> String {
        "\(host) is not an address this app trusts for plaintext HTTP: a .local or single-word host "
            + "name is answered by the network rather than by the app, so it can point anywhere and "
            + "the traffic could be intercepted. Use the machine's IP address (for example "
            + "192.168.1.20), or https://. "
            + "Over plaintext HTTP your \(secret) would cross the network unencrypted."
    }

    /// The refusal for a plaintext request to a host the app will not send a
    /// secret over.
    ///
    /// The wording follows what the app knows about the host, and every
    /// surface uses this one answer, so the settings field and the message
    /// that blocks the request cannot describe the same host differently.
    ///
    /// A name any device on the local network can claim is neither remote nor
    /// checkable, and its refusal names the fix. A host the app parsed and
    /// found to be public is a remote host. A host it could not parse is one
    /// it cannot use as a local address — calling that one remote would be a
    /// claim the app cannot make. Every refusal says what would cross the
    /// network, because that is the part the user acts on.
    static func plaintextTransportRefusal(
        host: String,
        subject: String,
        secret: String,
        localNoun: String
    ) -> String {
        if isUnqualifiedLocalName(host) {
            return unqualifiedLocalHostPlaintextMessage(host: host, secret: secret)
        }
        if isPublicAddress(host) {
            return "\(subject) uses plaintext HTTP to a remote host (\(host)). "
                + "Your \(secret) would be sent unencrypted. "
                + "Use https://, or configure a trusted local \(localNoun)."
        }
        return "\(subject) uses plaintext HTTP to a host this app cannot use as a local "
            + "address (\(host)). Your \(secret) would be sent unencrypted. "
            + "Use https://, or point this at an address the app can check."
    }

    /// A user-facing warning when the configured base URL would transmit the API
    /// key and transcript content to a non-local host over plaintext HTTP. Remote
    /// HTTPS and local HTTP (loopback/private/link-local) return `nil` so
    /// legitimate enterprise-proxy and local-provider workflows are not nagged.
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
        return plaintextTransportRefusal(
            host: host,
            subject: "This endpoint",
            secret: "API key and transcript text",
            localNoun: "endpoint"
        )
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
    /// link-local HTTP and remote HTTPS return nil. Reuses the host classifier from
    /// the AI base-URL guard (#472).
    var jiraBaseURLPlaintextWarning: String? {
        guard let url = jiraBaseURLValue,
              url.scheme?.lowercased() == "http",
              let host = url.host,
              !Self.isLocalEndpointHost(host) else {
            return nil
        }
        return Self.plaintextTransportRefusal(
            host: host,
            subject: "This Jira URL",
            secret: "email, API token and issue content",
            localNoun: "server"
        )
    }

    /// A blocking issue when the configured Jira base URL would put the account
    /// email, the API token and the issue content on the wire in the clear.
    ///
    /// The AI provider path hard-gates the identical condition (#953): a remote
    /// plaintext endpoint is a credential leak, not a preference, so warning
    /// about it was never enough — something has to refuse. The Jira export
    /// path consumes this instead of only showing `jiraBaseURLPlaintextWarning`.
    var jiraBaseURLCompatibilityIssue: String? {
        guard let url = jiraBaseURLValue,
              url.scheme?.lowercased() == "http",
              let host = url.host,
              !Self.isLocalEndpointHost(host) else {
            return nil
        }
        return "The Jira base URL uses plaintext HTTP to a remote host (\(host)). "
            + "Your Jira email, API token and issue content would cross the network "
            + "unencrypted. Use https://, or point this at a local address."
    }

    var localProviderSetupCommand: String {
        Self.localTranscriptionRunCommand
    }

    var localProviderSetupDownloadURL: URL {
        BugNarratorLinks.localTranscriptionDownload
    }

    var localProviderSetupDetail: String {
        "Install and start the local server in AI Engines settings, or choose another provider."
    }

    var localProviderUnreachableMessage: String {
        "BugNarrator could not reach the local transcription server at \(openAIBaseURLValue.absoluteString). \(localProviderSetupDetail)"
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


    var gitHubRepositoryDiscoveryIsReady: Bool {
        credentialIsAvailableForUserAction(
            value: trimmedGitHubToken,
            persistenceState: githubTokenPersistenceState
        )
    }



    var gitHubConfigurationValidationIsReady: Bool {
        gitHubRepositoryDiscoveryIsReady &&
            !normalizedGitHubRepositoryOwner.isEmpty &&
            !normalizedGitHubRepositoryName.isEmpty
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

    private func refreshLocalProviderReachabilityIfNeeded() {
        localProviderRefresh?.cancel()
        localProviderTask?.cancel()
        let requestID = UUID()
        localProviderRequestID = requestID
        guard aiProvider == .parakeetLocal else {
            localProviderReachability = .unknown
            lastLocalProviderReachabilityURL = nil
            return
        }

        let url = openAIBaseURLValue
        lastLocalProviderReachabilityURL = url
        if let localProviderReachabilityProbe {
            // Injected probes keep isolated tests synchronous and network-free.
            localProviderReachability = localProviderReachabilityProbe(url) ? .reachable : .unreachable
            return
        }

        var request = URLRequest(url: url.appendingPathComponent("health"))
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        localProviderTask = localProviderSession.dataTaskPublisher(for: request)
            .map { Self.isHealthyLocalProvider(data: $0.data, response: $0.response) }
            .replaceError(with: false)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reachable in
                guard let self, self.localProviderRequestID == requestID,
                      self.aiProvider == .parakeetLocal else { return }
                self.localProviderTask = nil
                let result: LocalProviderReachability = reachable ? .reachable : .unreachable
                if self.localProviderReachability != result {
                    self.localProviderReachability = result
                }
                let refresh = DispatchWorkItem { [weak self] in
                    self?.refreshLocalProviderReachabilityIfNeeded()
                }
                self.localProviderRefresh = refresh
                DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: refresh)
            }
    }

    func currentLocalProviderReachability() -> LocalProviderReachability {
        guard aiProvider == .parakeetLocal else { return .reachable }
        if let localProviderReachabilityProbe {
            return localProviderReachabilityProbe(openAIBaseURLValue) ? .reachable : .unreachable
        }
        if lastLocalProviderReachabilityURL != openAIBaseURLValue {
            refreshLocalProviderReachabilityIfNeeded()
        }
        return localProviderReachability
    }

    deinit {
        localProviderTask?.cancel()
        localProviderRefresh?.cancel()
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
    private let secretCoordinator: SettingsSecretCoordinator
    private let recordingPreferences: RecordingPreferencesStore
    private let trackerExportSettings: TrackerExportSettingsStore
    private let hotkeySettings: HotkeySettingsCoordinator
    private let launchAtLoginService: any LaunchAtLoginControlling
    private let legacyDefaultsDomains: [String]
    private let localProviderReachabilityProbe: ((URL) -> Bool)?
    private var localProviderTask: AnyCancellable?
    private let localProviderSession: URLSession
    private var localProviderRefresh: DispatchWorkItem?
    private var localProviderRequestID = UUID()
    private var hasLoaded = false
    private var isApplyingHotkeyChange = false
    private var isSynchronizingLaunchAtLogin = false
    private var lastLocalProviderReachabilityURL: URL?

    init(
        defaults: UserDefaults = .standard,
        keychainService: KeychainServicing = KeychainService(),
        launchAtLoginService: any LaunchAtLoginControlling = SystemLaunchAtLoginService(),
        legacyDefaultsDomains: [String]? = nil,
        localProviderReachabilityProbe: ((URL) -> Bool)? = nil,
        localProviderSession: URLSession = .shared
    ) {
        self.defaults = defaults
        self.recordingPreferences = RecordingPreferencesStore(defaults: defaults)
        self.trackerExportSettings = TrackerExportSettingsStore(defaults: defaults)
        self.secretCoordinator = SettingsSecretCoordinator(
            defaults: defaults,
            secretStore: KeychainSecretStore(keychainService: keychainService),
            aiProviderCredentialProviderKey: Keys.aiProviderCredentialProvider
        )
        let resolvedLegacyDefaultsDomains: [String]
        if let legacyDefaultsDomains {
            resolvedLegacyDefaultsDomains = legacyDefaultsDomains
        } else if defaults === UserDefaults.standard {
            resolvedLegacyDefaultsDomains = Self.defaultLegacyDefaultsDomains
        } else {
            resolvedLegacyDefaultsDomains = []
        }
        self.hotkeySettings = HotkeySettingsCoordinator(
            defaults: defaults,
            legacyDefaultsDomains: resolvedLegacyDefaultsDomains,
            keys: HotkeySettingsCoordinator.Keys(
                startRecording: Keys.startRecordingHotkeyShortcut,
                legacyRecording: Keys.legacyRecordingHotkeyShortcut,
                legacyStartRecording: Keys.legacyStartRecordingHotkeyShortcut,
                stopRecording: Keys.stopRecordingHotkeyShortcut,
                obsoleteMarker: Keys.markerHotkeyShortcut,
                captureScreenshot: Keys.screenshotHotkeyShortcut,
                didMigrateLegacyBuiltIns: Keys.didMigrateLegacyBuiltInHotkeys
            )
        )
        self.launchAtLoginService = launchAtLoginService
        self.localProviderReachabilityProbe = localProviderReachabilityProbe
        self.localProviderSession = localProviderSession
        self.legacyDefaultsDomains = resolvedLegacyDefaultsDomains

        load()
        hasLoaded = true
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
        if let savedProvider = stringValue(forKey: Keys.aiProvider).flatMap(AIProvider.init(rawValue:)) {
            aiProvider = savedProvider
        } else {
            let hadPreviousConfiguration = hasAPIKey ||
                boolValue(forKey: Keys.didMigrateLegacyBuiltInHotkeys) == true ||
                boolValue(forKey: Keys.hasCompletedFirstRunOnboarding) == true ||
                stringValue(forKey: Keys.preferredModel) != nil ||
                stringValue(forKey: Keys.openAIBaseURL) != nil ||
                boolValue(forKey: Keys.autoExtractIssues) != nil
            aiProvider = hadPreviousConfiguration ? .openAI : .parakeetLocal
        }
        // load() runs before didSet persistence is enabled. Save the decision
        // now so subsequent launches cannot reinterpret a once-fresh profile.
        defaults.set(aiProvider.rawValue, forKey: Keys.aiProvider)
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
        refreshLocalProviderReachabilityIfNeeded()

        autoCopyTranscript = boolValue(forKey: Keys.autoCopyTranscript) ?? false
        uploadScreenshotsForExtraction = boolValue(forKey: Keys.uploadScreenshotsForExtraction) ?? false
        autoSaveTranscript = boolValue(forKey: Keys.autoSaveTranscript) ?? true
        autoExtractIssues = boolValue(forKey: Keys.autoExtractIssues) ?? false
        hasOfferedIssueExtraction = boolValue(forKey: Keys.hasOfferedIssueExtraction) ?? false
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

        let hotkeys = hotkeySettings.loadAndNormalize()
        startRecordingHotkeyShortcut = hotkeys.startRecording
        stopRecordingHotkeyShortcut = hotkeys.stopRecording
        screenshotHotkeyShortcut = hotkeys.captureScreenshot

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
            let secret = secretCoordinator.load(
                slot: slot,
                allowInteraction: allowInteraction,
                includeLegacyServices: includeLegacyServices,
                aiProvider: aiProvider
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

            secretCoordinator.recordLoaded(secret, for: slot)
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

    private func hotkeyDidChange(_ changedAction: HotkeyAction, previousShortcut: HotkeyShortcut) {
        guard !isApplyingHotkeyChange else { return }
        let snapshot = currentHotkeySnapshot
        if let conflict = hotkeySettings.persistChange(
            action: changedAction,
            previousShortcut: previousShortcut,
            snapshot: snapshot
        ) {
            hotkeyConflictMessage = "\(conflict.shortcut.displayString) is already assigned to \(conflict.action.title). Clear it first or choose a different shortcut."
            conflictingHotkeyAction = conflict.action
            isApplyingHotkeyChange = true
            setHotkey(previousShortcut, for: changedAction)
            isApplyingHotkeyChange = false
        } else {
            hotkeyConflictMessage = nil
            conflictingHotkeyAction = nil
        }
    }

    /// Clears the binding for the named action, resolving a reported conflict.
    func clearHotkey(for action: HotkeyAction) {
        setHotkey(.disabled, for: action)
        hotkeyConflictMessage = nil
        conflictingHotkeyAction = nil
    }

    private var currentHotkeySnapshot: HotkeySettingsSnapshot {
        HotkeySettingsSnapshot(
            startRecording: startRecordingHotkeyShortcut,
            stopRecording: stopRecordingHotkeyShortcut,
            captureScreenshot: screenshotHotkeyShortcut
        )
    }

    private func setHotkey(_ shortcut: HotkeyShortcut, for action: HotkeyAction) {
        switch action {
        case .startRecording: startRecordingHotkeyShortcut = shortcut
        case .stopRecording: stopRecordingHotkeyShortcut = shortcut
        case .captureScreenshot: screenshotHotkeyShortcut = shortcut
        }
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

    @discardableResult
    private func persistSecret(_ value: String, for slot: SecretSlot) -> APIKeyPersistenceState {
        secretCoordinator.persist(value, for: slot, aiProvider: aiProvider)
    }

    private func loadSecret(
        for slot: SecretSlot,
        allowInteraction: Bool,
        includeLegacyServices: Bool
    ) -> LoadedSecret {
        secretCoordinator.load(
            slot: slot,
            allowInteraction: allowInteraction,
            includeLegacyServices: includeLegacyServices,
            aiProvider: aiProvider
        )
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
        setPersistenceState(
            secretCoordinator.stateAfterEditing(currentSecretValue(for: slot), for: slot),
            for: slot
        )
    }

    private func hasPendingSecretChanges(for slot: SecretSlot) -> Bool {
        persistenceState(for: slot) == .pendingSave
    }

    func credentialIsAvailableForUserAction(
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

    func aiProviderCredentialIsAvailableForCurrentProvider(
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
            // Untagged credentials predate provider selection and belong to OpenAI.
            // Readiness must never assign a secret to another endpoint.
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
    static let hasOfferedIssueExtraction = "settings.hasOfferedIssueExtraction"
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
    static let hasCompletedFirstRunOnboarding = "settings.hasCompletedFirstRunOnboarding"
    static let uploadScreenshotsForExtraction = "settings.uploadScreenshotsForExtraction"
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
