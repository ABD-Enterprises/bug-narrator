import AppKit
import Combine
import XCTest
@testable import BugNarrator

final class SettingsStoreTests: XCTestCase {
    func testDefaultLegacyDefaultsDomainsOnlyIncludeSessionMic() {
        XCTAssertEqual(
            SettingsStore.defaultLegacyDefaultsDomains,
            ["com.abdenterprises.sessionmic"]
        )
    }

    func testFirstLaunchStartsWithAllHotkeysDisabled() {
        let suiteName = "BugNarrator-SettingsNoHotkeyDefaultsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())

        XCTAssertEqual(store.startRecordingHotkeyShortcut, .disabled)
        XCTAssertEqual(store.stopRecordingHotkeyShortcut, .disabled)
        XCTAssertEqual(store.screenshotHotkeyShortcut, .disabled)
        XCTAssertEqual(store.jiraIssueType, "")
        XCTAssertFalse(store.systemAudioCaptureEnabled)
        XCTAssertEqual(store.recordingAudioSource, .microphone)
        XCTAssertFalse(store.hasAcceptedSystemAudioRecordingConsent)
    }

    func testSettingsPersistAcrossReloads() {
        let suiteName = "BugNarrator-SettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = MockKeychainService()
        let launchAtLoginService = MockLaunchAtLoginService()
        let firstStore = SettingsStore(
            defaults: defaults,
            keychainService: keychain,
            launchAtLoginService: launchAtLoginService
        )
        firstStore.apiKey = "persisted-api-key"
        firstStore.aiProvider = .localCompatible
        firstStore.openAIBaseURL = "http://localhost:1234/v1"
        firstStore.preferredModel = "whisper-1"
        firstStore.languageHint = "en"
        firstStore.transcriptionPrompt = "Focus on bugs."
        firstStore.issueExtractionModel = "gpt-4.1-mini"
        firstStore.autoCopyTranscript = false
        firstStore.autoSaveTranscript = false
        firstStore.autoExtractIssues = true
        firstStore.systemAudioCaptureEnabled = true
        firstStore.recordingAudioSource = .microphoneAndSystemAudio
        firstStore.hasAcceptedSystemAudioRecordingConsent = true
        firstStore.openAtStartup = true
        firstStore.debugMode = true
        firstStore.startRecordingHotkeyShortcut = HotkeyShortcut(
            keyCode: 1,
            modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue
        )
        firstStore.stopRecordingHotkeyShortcut = HotkeyShortcut(
            keyCode: 3,
            modifiers: NSEvent.ModifierFlags.command.union(.option).rawValue
        )
        firstStore.screenshotHotkeyShortcut = HotkeyShortcut(
            keyCode: 1,
            modifiers: NSEvent.ModifierFlags.command.union(.option).union(.control).rawValue
        )
        firstStore.githubToken = "fixture-github-token"
        firstStore.githubRepositoryOwner = "acme"
        firstStore.githubRepositoryName = "bugnarrator"
        firstStore.githubRepositoryID = "R_kgDOFixture"
        firstStore.githubDefaultLabels = "bug,triage"
        firstStore.jiraBaseURL = "acme.atlassian.net"
        firstStore.jiraEmail = "you@example.com"
        firstStore.jiraAPIToken = "fixture-jira-token"
        firstStore.jiraProjectKey = "FM"
        firstStore.jiraProjectID = "10000"
        firstStore.jiraIssueType = "Task"
        firstStore.jiraIssueTypeID = "10001"
        firstStore.refreshOpenAISecretForUserInitiatedAccess()
        firstStore.refreshExportSecretsForUserInitiatedAccess()

        let secondStore = SettingsStore(
            defaults: defaults,
            keychainService: keychain,
            launchAtLoginService: launchAtLoginService
        )

        XCTAssertEqual(secondStore.apiKey, "")
        XCTAssertEqual(secondStore.openAIAPIKeyForUserInitiatedAccess(), "persisted-api-key")
        XCTAssertEqual(secondStore.aiProvider, .localCompatible)
        XCTAssertEqual(secondStore.openAIBaseURL, "http://localhost:1234/v1")
        XCTAssertEqual(secondStore.preferredModel, "whisper-1")
        XCTAssertEqual(secondStore.languageHint, "en")
        XCTAssertEqual(secondStore.transcriptionPrompt, "Focus on bugs.")
        XCTAssertEqual(secondStore.issueExtractionModel, "gpt-4.1-mini")
        XCTAssertFalse(secondStore.autoCopyTranscript)
        XCTAssertFalse(secondStore.autoSaveTranscript)
        XCTAssertTrue(secondStore.autoExtractIssues)
        XCTAssertTrue(secondStore.systemAudioCaptureEnabled)
        XCTAssertEqual(secondStore.recordingAudioSource, .microphoneAndSystemAudio)
        XCTAssertTrue(secondStore.hasAcceptedSystemAudioRecordingConsent)
        XCTAssertTrue(secondStore.openAtStartup)
        XCTAssertTrue(secondStore.debugMode)
        XCTAssertEqual(secondStore.startRecordingHotkeyShortcut.keyCode, 1)
        XCTAssertEqual(
            secondStore.startRecordingHotkeyShortcut.modifiers,
            NSEvent.ModifierFlags.command.union(.shift).rawValue
        )
        XCTAssertEqual(secondStore.stopRecordingHotkeyShortcut.keyCode, 3)
        XCTAssertEqual(
            secondStore.stopRecordingHotkeyShortcut.modifiers,
            NSEvent.ModifierFlags.command.union(.option).rawValue
        )
        XCTAssertEqual(secondStore.screenshotHotkeyShortcut.keyCode, 1)
        XCTAssertEqual(
            secondStore.screenshotHotkeyShortcut.modifiers,
            NSEvent.ModifierFlags.command.union(.option).union(.control).rawValue
        )
        XCTAssertEqual(secondStore.githubToken, "fixture-github-token")
        XCTAssertEqual(secondStore.githubRepositoryOwner, "acme")
        XCTAssertEqual(secondStore.githubRepositoryName, "bugnarrator")
        XCTAssertEqual(secondStore.githubRepositoryID, "R_kgDOFixture")
        XCTAssertEqual(secondStore.githubDefaultLabelsList, ["bug", "triage"])
        XCTAssertEqual(secondStore.jiraBaseURL, "acme.atlassian.net")
        XCTAssertEqual(secondStore.jiraEmail, "you@example.com")
        XCTAssertEqual(secondStore.jiraAPIToken, "fixture-jira-token")
        XCTAssertEqual(secondStore.jiraProjectKey, "FM")
        XCTAssertEqual(secondStore.jiraProjectID, "10000")
        XCTAssertEqual(secondStore.jiraIssueType, "Task")
        XCTAssertEqual(secondStore.jiraIssueTypeID, "10001")
    }

    func testAPIKeyStaysOutOfUserDefaultsWhenKeychainSucceeds() {
        let suiteName = "BugNarrator-SettingsNoDefaultsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = MockKeychainService()
        let store = SettingsStore(defaults: defaults, keychainService: keychain)
        store.apiKey = "saved-in-keychain"

        XCTAssertFalse(defaults.dictionaryRepresentation().keys.contains { $0.localizedCaseInsensitiveContains("apikey") })
        XCTAssertEqual(store.apiKeyPersistenceState, .pendingSave)
        XCTAssertTrue(keychain.values.isEmpty)

        store.refreshOpenAISecretForUserInitiatedAccess()

        XCTAssertEqual(store.apiKeyPersistenceState, .keychain)
    }

    func testJiraEmailStaysOutOfUserDefaultsWhenKeychainSucceeds() {
        let suiteName = "BugNarrator-SettingsJiraEmailNoDefaultsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = MockKeychainService()
        let store = SettingsStore(defaults: defaults, keychainService: keychain)
        store.jiraEmail = "secure@example.com"

        XCTAssertNil(defaults.string(forKey: "settings.jiraEmail"))
        XCTAssertEqual(store.jiraEmailPersistenceState, .pendingSave)
        XCTAssertTrue(keychain.values.isEmpty)

        store.refreshExportSecretsForUserInitiatedAccess()

        XCTAssertEqual(store.jiraEmailPersistenceState, .keychain)
        XCTAssertEqual(
            keychain.values["BugNarrator.Jira::jira-email"],
            "secure@example.com"
        )
    }

    func testAPIKeyFallsBackToSessionOnlyWhenKeychainWriteFails() {
        let suiteName = "BugNarrator-SettingsFallbackTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = MockKeychainService()
        keychain.setError = AppError.storageFailure("Keychain unavailable")

        let firstStore = SettingsStore(defaults: defaults, keychainService: keychain)
        firstStore.apiKey = "fallback-key"
        firstStore.refreshOpenAISecretForUserInitiatedAccess()

        let secondStore = SettingsStore(defaults: defaults, keychainService: keychain)

        XCTAssertEqual(firstStore.apiKeyPersistenceState, .sessionOnly)
        XCTAssertEqual(secondStore.apiKey, "")
    }

    func testMaskedAPIKeyOnlyExposesSuffix() {
        let suiteName = "BugNarrator-SettingsMaskTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())
        store.apiKey = "fixture-openai-key-1234"

        XCTAssertEqual(store.maskedAPIKey, "••••••••1234")
    }

    func testOpenAIBaseURLNormalizesEnterpriseEndpoint() {
        XCTAssertEqual(
            SettingsStore.normalizedOpenAIBaseURL(from: "proxy.example.com/openai/").absoluteString,
            "https://proxy.example.com/openai"
        )
        XCTAssertEqual(
            SettingsStore.normalizedOpenAIBaseURL(from: "").absoluteString,
            "https://api.openai.com"
        )
    }

    func testLocalProviderBaseURLDefaultsToHTTPWhenSchemeIsOmitted() {
        XCTAssertEqual(
            SettingsStore.normalizedOpenAIBaseURL(
                from: "localhost:1234/v1",
                provider: .localCompatible
            ).absoluteString,
            "http://localhost:1234/v1"
        )
        XCTAssertEqual(
            SettingsStore.normalizedOpenAIBaseURL(
                from: "localhost:8422",
                provider: .parakeetLocal
            ).absoluteString,
            "http://localhost:8422"
        )
    }

    func testTranscriptionRequestUsesNormalizedTranscriptionSettings() {
        let suiteName = "BugNarrator-TranscriptionRequestSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())
        store.preferredModel = "  gpt-4o-transcribe  "
        store.languageHint = "  en  "
        store.transcriptionPrompt = "  Focus on tester narration.  "
        store.openAIBaseURL = "gateway.example.com/openai/"

        let request = store.transcriptionRequest

        XCTAssertEqual(request.model, "gpt-4o-transcribe")
        XCTAssertEqual(request.languageHint, "en")
        XCTAssertEqual(request.prompt, "Focus on tester narration.")
        XCTAssertEqual(request.apiBaseURL.absoluteString, "https://gateway.example.com/openai")
    }

    func testOpenAIProviderDoesNotUsePersistedParakeetTranscriptionModel() {
        let suiteName = "BugNarrator-SettingsOpenAIParakeetModelTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AIProvider.openAI.rawValue, forKey: "settings.aiProvider")
        defaults.set("parakeet-tdt-0.6b-v3", forKey: "settings.preferredModel")

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())

        XCTAssertEqual(store.preferredModel, "whisper-1")
        XCTAssertEqual(store.transcriptionRequest.model, "whisper-1")
        XCTAssertEqual(defaults.string(forKey: "settings.preferredModel"), "whisper-1")
    }

    func testOpenAIProviderUsesCuratedTranscriptionModelChoices() {
        let suiteName = "BugNarrator-SettingsOpenAIModelChoicesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())

        XCTAssertEqual(
            store.transcriptionModelChoices.map(\.id),
            [
                "whisper-1",
                "gpt-4o-mini-transcribe",
                "gpt-4o-transcribe",
                "gpt-4o-transcribe-diarize"
            ]
        )

        store.preferredModel = "not-an-openai-transcription-model"

        XCTAssertEqual(store.transcriptionRequest.model, "whisper-1")
    }

    func testOpenAIProviderUsesCuratedIssueExtractionModelChoices() {
        let suiteName = "BugNarrator-SettingsOpenAIIssueModelChoicesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AIProvider.openAI.rawValue, forKey: "settings.aiProvider")
        defaults.set("not-a-chat-model", forKey: "settings.issueExtractionModel")

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())

        XCTAssertEqual(
            store.issueExtractionModelChoices.map(\.id),
            [
                "gpt-4.1-mini",
                "gpt-4.1-nano",
                "gpt-4.1"
            ]
        )
        XCTAssertEqual(store.issueExtractionModel, "gpt-4.1-mini")
        XCTAssertEqual(defaults.string(forKey: "settings.issueExtractionModel"), "gpt-4.1-mini")
    }

    func testSwitchingBackToOpenAIResetsParakeetTranscriptionModel() {
        let suiteName = "BugNarrator-SettingsProviderModelSwitchTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())
        store.aiProvider = .parakeetLocal

        XCTAssertEqual(store.preferredModel, "parakeet-tdt-0.6b-v3")

        store.aiProvider = .openAI

        XCTAssertEqual(store.preferredModel, "whisper-1")
        XCTAssertEqual(store.transcriptionRequest.model, "whisper-1")
        XCTAssertEqual(defaults.string(forKey: "settings.preferredModel"), "whisper-1")
    }

    func testLocalCompatibleProviderCanUseSafeDefaultBaseURLButRequiresLocalModels() {
        let suiteName = "BugNarrator-SettingsProviderCompatibility-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())
        store.aiProvider = .localCompatible

        XCTAssertEqual(
            store.aiProviderCompatibilityIssue,
            "Choose a local transcription model instead of whisper-1 for the Local-Compatible provider."
        )
        XCTAssertEqual(store.openAIBaseURLValue.absoluteString, "http://localhost:1234/v1")

        store.preferredModel = "whisper-large-v3"
        XCTAssertEqual(
            store.aiProviderCompatibilityIssue,
            "Choose a local issue extraction model instead of gpt-4.1-mini for the Local-Compatible provider."
        )

        store.issueExtractionModel = "llama3.1:8b"
        XCTAssertNil(store.aiProviderCompatibilityIssue)
        XCTAssertEqual(store.aiProviderCredentialForUserInitiatedAccess(), "")
    }

    func testOpenAICompatibleProviderRequiresNonDefaultBaseURL() {
        let suiteName = "BugNarrator-SettingsOpenAICompatible-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())
        store.aiProvider = .openAICompatible
        store.apiKey = "enterprise-token"

        XCTAssertEqual(
            store.aiProviderCompatibilityIssue,
            "Choose a non-default API base URL for the OpenAI-Compatible provider."
        )

        store.openAIBaseURL = "https://gateway.example.com/openai"
        XCTAssertNil(store.aiProviderCompatibilityIssue)
        XCTAssertTrue(store.hasUsableAIProviderCredential)
    }

    func testParakeetProviderCanUseSafeDefaultBaseURLWithoutAPIKey() {
        let suiteName = "BugNarrator-SettingsParakeet-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())
        store.aiProvider = .parakeetLocal
        store.openAIBaseURL = ""

        XCTAssertNil(store.aiProviderCompatibilityIssue)
        XCTAssertTrue(store.hasUsableAIProviderCredential)
        XCTAssertTrue(store.aiProviderConfigurationIsReady)
        XCTAssertEqual(store.openAIBaseURLValue.absoluteString, "http://localhost:8422")
        XCTAssertEqual(store.aiProviderCredentialForUserInitiatedAccess(), "")
    }

    func testOpenAIProviderConfigurationRequiresUsableCredential() {
        let suiteName = "BugNarrator-SettingsOpenAIReadiness-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())

        XCTAssertFalse(store.aiProviderConfigurationIsReady)

        store.apiKey = "sk-fixture"

        XCTAssertTrue(store.aiProviderConfigurationIsReady)
    }

    func testOpenAIProviderConfigurationTreatsSavedKeychainCredentialAsReady() {
        let suiteName = "BugNarrator-SettingsOpenAIKeychainReadiness-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = MockKeychainService()
        let firstStore = SettingsStore(defaults: defaults, keychainService: keychain)
        firstStore.apiKey = "sk-fixture"
        firstStore.refreshOpenAISecretForUserInitiatedAccess()

        let secondStore = SettingsStore(defaults: defaults, keychainService: keychain)

        XCTAssertEqual(secondStore.apiKey, "")
        XCTAssertEqual(secondStore.apiKeyPersistenceState, .keychain)
        XCTAssertTrue(secondStore.hasAPIKey)
        XCTAssertTrue(secondStore.aiProviderConfigurationIsReady)
    }

    func testLocalProviderConfigurationReadinessDoesNotRequireAPIKeyState() {
        let suiteName = "BugNarrator-SettingsLocalProviderReadiness-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())
        store.aiProvider = .localCompatible

        XCTAssertFalse(store.aiProviderConfigurationIsReady)

        store.preferredModel = "whisper-large-v3"
        store.issueExtractionModel = "llama3.1:8b"

        XCTAssertEqual(store.apiKeyPersistenceState, .empty)
        XCTAssertNil(store.aiProviderCompatibilityIssue)
        XCTAssertTrue(store.hasUsableAIProviderCredential)
        XCTAssertTrue(store.aiProviderConfigurationIsReady)
    }

    func testLocalCompatibleProviderForwardsCredentialSavedForLocalProvider() {
        let suiteName = "BugNarrator-SettingsLocalProviderCredential-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = MockKeychainService()
        let firstStore = SettingsStore(defaults: defaults, keychainService: keychain)
        firstStore.aiProvider = .localCompatible
        firstStore.preferredModel = "whisper-large-v3"
        firstStore.issueExtractionModel = "llama3.1:8b"
        firstStore.apiKey = "local-provider-token"

        XCTAssertEqual(
            firstStore.aiProviderCredentialForUserInitiatedAccess(),
            "local-provider-token"
        )

        let secondStore = SettingsStore(defaults: defaults, keychainService: keychain)

        XCTAssertEqual(secondStore.aiProvider, .localCompatible)
        XCTAssertEqual(
            secondStore.aiProviderCredentialForUserInitiatedAccess(),
            "local-provider-token"
        )
    }

    func testHostedProvidersDoNotReuseCredentialSavedForLocalProvider() {
        let suiteName = "BugNarrator-SettingsHostedProviderCredentialIsolation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = MockKeychainService()
        let firstStore = SettingsStore(defaults: defaults, keychainService: keychain)
        firstStore.aiProvider = .localCompatible
        firstStore.preferredModel = "whisper-large-v3"
        firstStore.issueExtractionModel = "llama3.1:8b"
        firstStore.apiKey = "local-provider-token"
        _ = firstStore.aiProviderCredentialForUserInitiatedAccess()

        let secondStore = SettingsStore(defaults: defaults, keychainService: keychain)
        secondStore.aiProvider = .openAI

        XCTAssertFalse(secondStore.hasUsableAIProviderCredential)
        XCTAssertNil(secondStore.aiProviderCredentialForUserInitiatedAccess())

        secondStore.aiProvider = .openAICompatible
        secondStore.openAIBaseURL = "https://gateway.example.com/openai"

        XCTAssertFalse(secondStore.hasUsableAIProviderCredential)
        XCTAssertNil(secondStore.aiProviderCredentialForUserInitiatedAccess())
    }

    func testOpenAICompatibleProviderDoesNotReuseSavedOpenAICredential() {
        let suiteName = "BugNarrator-SettingsCompatibleProviderCredentialIsolation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = MockKeychainService()
        let firstStore = SettingsStore(defaults: defaults, keychainService: keychain)
        firstStore.aiProvider = .openAI
        firstStore.apiKey = "sk-openai-token"
        firstStore.refreshOpenAISecretForUserInitiatedAccess()

        let secondStore = SettingsStore(defaults: defaults, keychainService: keychain)
        secondStore.aiProvider = .openAICompatible
        secondStore.openAIBaseURL = "https://gateway.example.com/openai"

        XCTAssertFalse(secondStore.hasUsableAIProviderCredential)
        XCTAssertNil(secondStore.aiProviderCredentialForUserInitiatedAccess())
    }

    func testSelectedProviderCredentialStatusIgnoresCredentialsSavedForOtherProviders() {
        let suiteName = "BugNarrator-SettingsSelectedProviderCredentialStatus-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = MockKeychainService()
        let firstStore = SettingsStore(defaults: defaults, keychainService: keychain)
        firstStore.aiProvider = .openAI
        firstStore.apiKey = "sk-openai-token"
        firstStore.refreshOpenAISecretForUserInitiatedAccess()

        let secondStore = SettingsStore(defaults: defaults, keychainService: keychain)
        secondStore.aiProvider = .openAICompatible

        XCTAssertTrue(secondStore.hasAPIKey)
        XCTAssertFalse(secondStore.hasSelectedAIProviderCredential)
        XCTAssertEqual(secondStore.selectedAIProviderCredentialPersistenceState, .empty)
        XCTAssertEqual(secondStore.maskedSelectedAIProviderCredential, "No key saved")
        XCTAssertEqual(
            secondStore.selectedAIProviderCredentialStorageDescription,
            "BugNarrator never ships with an API key. Paste your own OpenAI-Compatible credential to enable transcription."
        )
    }

    func testSelectedProviderCredentialStatusIncludesLocalProviderCredential() {
        let suiteName = "BugNarrator-SettingsSelectedLocalProviderCredentialStatus-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = MockKeychainService()
        let firstStore = SettingsStore(defaults: defaults, keychainService: keychain)
        firstStore.aiProvider = .localCompatible
        firstStore.apiKey = "local-provider-token"
        _ = firstStore.aiProviderCredentialForUserInitiatedAccess()

        let secondStore = SettingsStore(defaults: defaults, keychainService: keychain)
        secondStore.aiProvider = .localCompatible

        XCTAssertTrue(secondStore.hasSelectedAIProviderCredential)
        XCTAssertEqual(secondStore.selectedAIProviderCredentialPersistenceState, .keychain)
        XCTAssertEqual(secondStore.maskedSelectedAIProviderCredential, "Saved key")
    }

    func testSelectedProviderCredentialStatusIgnoresDraftCredentialForParakeetProvider() {
        let suiteName = "BugNarrator-SettingsSelectedParakeetProviderCredentialStatus-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())
        store.apiKey = "sk-draft-openai-key"
        store.aiProvider = .parakeetLocal

        XCTAssertEqual(store.selectedAIProviderCredentialPersistenceState, .empty)
        XCTAssertFalse(store.hasSelectedAIProviderCredential)
        XCTAssertEqual(store.maskedSelectedAIProviderCredential, "No key required")
        XCTAssertEqual(
            store.selectedAIProviderCredentialStorageDescription,
            "Local Parakeet does not use an API key. Check the local server connection before transcribing."
        )
    }

    func testParakeetProviderRejectsAutomaticIssueExtraction() {
        let suiteName = "BugNarrator-SettingsParakeetAutoExtraction-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())
        store.aiProvider = .parakeetLocal
        store.openAIBaseURL = "http://localhost:8422"
        store.autoExtractIssues = true

        XCTAssertFalse(store.supportsIssueExtraction)
        XCTAssertEqual(
            store.aiProviderCompatibilityIssue,
            "Turn off automatic issue extraction or choose a provider with a chat completion model."
        )
        XCTAssertFalse(store.aiProviderConfigurationIsReady)
    }

    func testNonAPIKeyProviderDoesNotForwardSavedOpenAIKey() {
        let suiteName = "BugNarrator-SettingsNonAPIKeyProviderLeak-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())
        store.aiProvider = .openAI
        store.apiKey = "sk-saved-openai-key"
        XCTAssertEqual(store.aiProviderCredentialForUserInitiatedAccess(), "sk-saved-openai-key")

        store.aiProvider = .parakeetLocal
        store.openAIBaseURL = "http://localhost:8422"

        XCTAssertEqual(
            store.aiProviderCredentialForUserInitiatedAccess(),
            "",
            "Switching to a non-requiresAPIKey provider must not return the saved OpenAI key."
        )

        store.aiProvider = .localCompatible
        store.openAIBaseURL = "http://localhost:1234/v1"
        XCTAssertEqual(
            store.aiProviderCredentialForUserInitiatedAccess(),
            "",
            "A non-requiresAPIKey provider must never forward a saved OpenAI key."
        )
    }

    func testSettingsLoadFromLegacyDefaultsDomain() throws {
        let suiteName = "BugNarrator-SettingsLegacyDefaultsTests-\(UUID().uuidString)"
        let legacyDomainName = "com.abdenterprises.sessionmic.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.removePersistentDomain(forName: legacyDomainName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            defaults.removePersistentDomain(forName: legacyDomainName)
        }

        let shortcut = HotkeyShortcut(
            keyCode: 2,
            modifiers: NSEvent.ModifierFlags.command.union(.option).rawValue
        )
        let shortcutData = try XCTUnwrap(try? JSONEncoder().encode(shortcut))

        defaults.setPersistentDomain(
            [
                "settings.preferredModel": "whisper-1",
                "settings.autoSaveTranscript": false,
                "settings.githubRepositoryName": "bugnarrator",
                "settings.recordingHotkeyShortcut": shortcutData
            ],
            forName: legacyDomainName
        )

        let store = SettingsStore(
            defaults: defaults,
            keychainService: MockKeychainService(),
            legacyDefaultsDomains: [legacyDomainName]
        )

        XCTAssertEqual(store.preferredModel, "whisper-1")
        XCTAssertFalse(store.autoSaveTranscript)
        XCTAssertEqual(store.githubRepositoryName, "bugnarrator")
        XCTAssertEqual(store.startRecordingHotkeyShortcut.keyCode, 2)
        XCTAssertEqual(
            defaults.string(forKey: "settings.githubRepositoryName"),
            "bugnarrator"
        )
    }

    func testLegacyPlaintextJiraEmailIsMigratedToSecureStorage() {
        let suiteName = "BugNarrator-SettingsLegacyJiraEmailTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("legacy@example.com", forKey: "settings.jiraEmail")

        let keychain = MockKeychainService()
        let store = SettingsStore(defaults: defaults, keychainService: keychain)

        XCTAssertEqual(store.jiraEmail, "legacy@example.com")
        XCTAssertEqual(store.jiraEmailPersistenceState, .keychain)
        XCTAssertNil(defaults.string(forKey: "settings.jiraEmail"))
        XCTAssertEqual(
            keychain.values["BugNarrator.Jira::jira-email"],
            "legacy@example.com"
        )
    }

    func testSecureDraftEditsDoNotTouchKeychainUntilUserInitiatesSave() {
        let suiteName = "BugNarrator-SettingsDeferredSecretWriteTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = MockKeychainService()
        let store = SettingsStore(defaults: defaults, keychainService: keychain)
        store.apiKey = "draft-openai-key"
        store.jiraAPIToken = "draft-jira-token"

        XCTAssertEqual(store.apiKeyPersistenceState, .pendingSave)
        XCTAssertEqual(store.jiraTokenPersistenceState, .pendingSave)
        XCTAssertTrue(keychain.values.isEmpty)

        store.refreshOpenAISecretForUserInitiatedAccess()
        store.refreshExportSecretsForUserInitiatedAccess()

        XCTAssertEqual(store.apiKeyPersistenceState, .keychain)
        XCTAssertEqual(store.jiraTokenPersistenceState, .keychain)
        XCTAssertEqual(keychain.values["BugNarrator.OpenAI::openai-api-key"], "draft-openai-key")
        XCTAssertEqual(keychain.values["BugNarrator.Jira::jira-api-token"], "draft-jira-token")
    }

    func testInvalidRecordingAudioSourceFallsBackToMicrophone() {
        let suiteName = "BugNarrator-RecordingAudioSourceInvalidTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "settings.systemAudioCaptureEnabled")
        defaults.set("not-a-source", forKey: "settings.recordingAudioSource")

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())

        XCTAssertEqual(store.recordingAudioSource, .microphone)
    }

    func testSystemAudioSourceResetsWhenFeatureFlagIsDisabled() {
        let suiteName = "BugNarrator-RecordingAudioSourceFlagTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "settings.systemAudioCaptureEnabled")
        defaults.set(RecordingAudioSource.systemAudio.rawValue, forKey: "settings.recordingAudioSource")

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())

        XCTAssertEqual(store.recordingAudioSource, .microphone)
        XCTAssertEqual(defaults.string(forKey: "settings.recordingAudioSource"), RecordingAudioSource.microphone.rawValue)
    }

    func testTrackerSetupReadinessDoesNotRequireLoadedPickerSelections() {
        let suiteName = "BugNarrator-SettingsTrackerSetupReadinessTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())

        XCTAssertFalse(store.gitHubRepositoryDiscoveryIsReady)
        XCTAssertFalse(store.gitHubConfigurationValidationIsReady)
        XCTAssertFalse(store.jiraProjectDiscoveryIsReady)

        store.githubToken = "fixture-github-token"
        XCTAssertTrue(store.gitHubRepositoryDiscoveryIsReady)
        XCTAssertFalse(store.gitHubConfigurationValidationIsReady)

        store.githubRepositoryOwner = "acme"
        store.githubRepositoryName = "bugnarrator"
        XCTAssertTrue(store.gitHubConfigurationValidationIsReady)
        XCTAssertNotNil(store.githubExportConfiguration)

        store.jiraBaseURL = "https://digitaltransformation-csra.atlassian.net/"
        store.jiraEmail = "alan.deffenderfer@gdit.com"
        store.jiraAPIToken = "fixture-jira-token"

        XCTAssertTrue(store.jiraProjectDiscoveryIsReady)
        XCTAssertEqual(store.jiraConnectionConfiguration?.baseURL.scheme, "https")
        XCTAssertEqual(store.jiraConnectionConfiguration?.baseURL.host, "digitaltransformation-csra.atlassian.net")
        XCTAssertNil(store.jiraExportConfiguration)
    }

    func testExportConfigurationsMatchProviderSelectionRequirements() {
        let suiteName = "BugNarrator-SettingsVerifiedTrackerSelectionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())
        store.githubToken = "fixture-github-token"
        store.githubRepositoryOwner = "acme"
        store.githubRepositoryName = "bugnarrator"
        store.jiraBaseURL = "acme.atlassian.net"
        store.jiraEmail = "you@example.com"
        store.jiraAPIToken = "fixture-jira-token"
        store.jiraProjectKey = "FM"
        store.jiraIssueType = "Task"

        XCTAssertNotNil(store.githubExportConfiguration)
        XCTAssertNil(store.githubExportConfiguration?.repositoryID)
        XCTAssertNotNil(store.jiraExportConfiguration)
        XCTAssertNil(store.jiraExportConfiguration?.projectID)
        XCTAssertEqual(store.jiraExportConfiguration?.issueTypeID, "")
        XCTAssertEqual(store.jiraExportConfiguration?.issueTypeName, "Task")

        store.githubRepositoryID = "R_kgDOFixture"
        store.jiraProjectID = "10000"
        store.jiraIssueTypeID = "10001"

        XCTAssertNotNil(store.githubExportConfiguration)
        XCTAssertNotNil(store.jiraExportConfiguration)
    }

    func testJiraTokenDraftOnlyPublishesPendingSaveTransitionOnce() {
        let suiteName = "BugNarrator-JiraTokenPendingSavePublisherTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())
        var observedStates: [APIKeyPersistenceState] = []
        let cancellable = store.$jiraTokenPersistenceState.sink { observedStates.append($0) }
        defer { cancellable.cancel() }

        store.jiraAPIToken = "a"
        store.jiraAPIToken = "ab"
        store.jiraAPIToken = "abc"

        XCTAssertEqual(observedStates, [.empty, .pendingSave])
    }

    func testDuplicateHotkeyAssignmentsAreRejectedAndKeepExistingAction() {
        let suiteName = "BugNarrator-SettingsHotkeyConflictTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())
        let duplicateShortcut = HotkeyShortcut(
            keyCode: 7,
            modifiers: NSEvent.ModifierFlags.command.union(.option).rawValue
        )

        store.startRecordingHotkeyShortcut = duplicateShortcut
        store.stopRecordingHotkeyShortcut = duplicateShortcut

        XCTAssertEqual(store.startRecordingHotkeyShortcut, duplicateShortcut)
        XCTAssertEqual(store.stopRecordingHotkeyShortcut, .disabled)
        XCTAssertEqual(
            store.hotkeyConflictMessage,
            "\(duplicateShortcut.displayString) is already assigned to Start Recording. Clear it first or choose a different shortcut."
        )
    }

    func testLegacyBuiltInShortcutsAreClearedDuringMigration() throws {
        let suiteName = "BugNarrator-SettingsHotkeyMigrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let encoder = JSONEncoder()
        try defaults.set(
            encoder.encode(try XCTUnwrap(HotkeyAction.startRecording.legacyBuiltInShortcut)),
            forKey: "settings.startRecordingHotkeyShortcut"
        )
        try defaults.set(
            encoder.encode(try XCTUnwrap(HotkeyAction.stopRecording.legacyBuiltInShortcut)),
            forKey: "settings.stopRecordingHotkeyShortcut"
        )
        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())

        XCTAssertEqual(store.startRecordingHotkeyShortcut, .disabled)
        XCTAssertEqual(store.stopRecordingHotkeyShortcut, .disabled)
        XCTAssertEqual(defaults.bool(forKey: "settings.didMigrateLegacyBuiltInHotkeys"), true)
    }

    func testObsoleteMarkerHotkeyIsRemovedDuringLoad() throws {
        let suiteName = "BugNarrator-SettingsObsoleteMarkerHotkeyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try defaults.set(
            JSONEncoder().encode(
                HotkeyShortcut(
                    keyCode: 46,
                    modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue
                )
            ),
            forKey: "settings.markerHotkeyShortcut"
        )

        _ = SettingsStore(defaults: defaults, keychainService: MockKeychainService())

        XCTAssertNil(defaults.object(forKey: "settings.markerHotkeyShortcut"))
    }

    func testSettingsLoadLegacyKeychainServiceAndMigrateToBugNarratorNamespace() {
        let suiteName = "BugNarrator-SettingsLegacyKeychainTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = MockKeychainService()
        keychain.values["SessionMic.OpenAI::openai-api-key"] = "legacy-api-key"

        let store = SettingsStore(defaults: defaults, keychainService: keychain)

        XCTAssertEqual(store.apiKey, "")
        XCTAssertEqual(store.openAIAPIKeyForUserInitiatedAccess(), "legacy-api-key")
        XCTAssertEqual(
            keychain.values["BugNarrator.OpenAI::openai-api-key"],
            "legacy-api-key"
        )
        XCTAssertNil(keychain.values["SessionMic.OpenAI::openai-api-key"])
    }

    func testStartupShowsKeychainLockedStateWithoutUnlockPrompt() {
        let suiteName = "BugNarrator-SettingsKeychainLockedTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = MockKeychainService()
        keychain.values["BugNarrator.OpenAI::openai-api-key"] = "locked-api-key"
        keychain.interactionRequiredKeys = ["BugNarrator.OpenAI::openai-api-key"]

        let store = SettingsStore(defaults: defaults, keychainService: keychain)

        XCTAssertEqual(store.apiKey, "")
        XCTAssertEqual(store.apiKeyPersistenceState, .keychainLocked)
        XCTAssertEqual(store.maskedAPIKey, "Saved key locked")
        XCTAssertEqual(
            store.apiKeyStorageDescription,
            "Stored in your macOS Keychain. BugNarrator will only prompt to unlock it when you validate the key or run an action that needs it."
        )
        XCTAssertTrue(
            keychain.readRequests.contains {
                $0.service == "BugNarrator.OpenAI" && !$0.allowInteraction
            }
        )
    }

    func testStartupSkipsInteractiveLegacyKeychainPromptUntilUserInitiatesAccess() {
        let suiteName = "BugNarrator-SettingsDeferredLegacyKeychainTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = MockKeychainService()
        let legacyKey = "SessionMic.OpenAI::openai-api-key"
        keychain.values[legacyKey] = "legacy-api-key"
        keychain.interactionRequiredKeys = [legacyKey]

        let store = SettingsStore(defaults: defaults, keychainService: keychain)

        XCTAssertEqual(store.apiKey, "")
        XCTAssertEqual(store.apiKeyPersistenceState, .keychainLocked)
        XCTAssertTrue(
            keychain.readRequests.contains {
                $0.service == "SessionMic.OpenAI" && !$0.allowInteraction
            }
        )
        XCTAssertNil(keychain.values["BugNarrator.OpenAI::openai-api-key"])

        let resolvedAPIKey = store.openAIAPIKeyForUserInitiatedAccess()

        XCTAssertEqual(resolvedAPIKey, "legacy-api-key")
        XCTAssertEqual(store.apiKey, "")
        XCTAssertTrue(
            keychain.readRequests.contains {
                $0.service == "SessionMic.OpenAI" && $0.allowInteraction
            }
        )
        XCTAssertEqual(
            keychain.values["BugNarrator.OpenAI::openai-api-key"],
            "legacy-api-key"
        )
    }

    func testStartupSkipsInteractiveLegacyExportKeychainPromptsUntilUserInitiatesAccess() {
        let suiteName = "BugNarrator-SettingsDeferredExportKeychainTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = MockKeychainService()
        let legacyGitHubKey = "SessionMic.GitHub::github-token"
        let legacyJiraKey = "SessionMic.Jira::jira-api-token"
        keychain.values[legacyGitHubKey] = "legacy-fixture-github-token"
        keychain.values[legacyJiraKey] = "legacy-fixture-jira-token"
        keychain.interactionRequiredKeys = [legacyGitHubKey, legacyJiraKey]

        let store = SettingsStore(defaults: defaults, keychainService: keychain)

        XCTAssertEqual(store.githubToken, "")
        XCTAssertEqual(store.jiraAPIToken, "")
        XCTAssertEqual(store.githubTokenPersistenceState, .keychainLocked)
        XCTAssertEqual(store.jiraTokenPersistenceState, .keychainLocked)
        XCTAssertTrue(
            keychain.readRequests.contains {
                $0.service == "SessionMic.GitHub" && !$0.allowInteraction
            }
        )
        XCTAssertTrue(
            keychain.readRequests.contains {
                $0.service == "SessionMic.Jira" && !$0.allowInteraction
            }
        )

        store.refreshExportSecretsForUserInitiatedAccess()

        XCTAssertEqual(store.githubToken, "legacy-fixture-github-token")
        XCTAssertEqual(store.jiraAPIToken, "legacy-fixture-jira-token")
        XCTAssertTrue(
            keychain.readRequests.contains {
                $0.service == "SessionMic.GitHub" && $0.allowInteraction
            }
        )
        XCTAssertTrue(
            keychain.readRequests.contains {
                $0.service == "SessionMic.Jira" && $0.allowInteraction
            }
        )
        XCTAssertEqual(
            keychain.values["BugNarrator.GitHub::github-token"],
            "legacy-fixture-github-token"
        )
        XCTAssertEqual(
            keychain.values["BugNarrator.Jira::jira-api-token"],
            "legacy-fixture-jira-token"
        )
    }

    func testMaskedExportTokensOnlyExposeSuffix() {
        let suiteName = "BugNarrator-SettingsExportMaskTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())
        store.githubToken = "fixture-github-token-9876"
        store.jiraAPIToken = "fixture-jira-token-4321"

        XCTAssertEqual(store.maskedGitHubToken, "••••••••9876")
        XCTAssertEqual(store.maskedJiraAPIToken, "••••••••4321")
    }

    func testRemoveAPIKeyClearsStoredValue() {
        let suiteName = "BugNarrator-SettingsRemoveTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = MockKeychainService()
        let store = SettingsStore(defaults: defaults, keychainService: keychain)
        store.apiKey = "to-be-removed"

        store.removeAPIKey()

        XCTAssertEqual(store.apiKey, "")
        XCTAssertEqual(store.apiKeyPersistenceState, .empty)
        XCTAssertTrue(keychain.values.isEmpty)
    }

    func testRemoveExportTokensClearsStoredValues() {
        let suiteName = "BugNarrator-SettingsRemoveExportTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = MockKeychainService()
        let store = SettingsStore(defaults: defaults, keychainService: keychain)
        store.githubToken = "github-remove"
        store.jiraAPIToken = "jira-remove"

        store.removeGitHubToken()
        store.removeJiraAPIToken()

        XCTAssertEqual(store.githubToken, "")
        XCTAssertEqual(store.jiraAPIToken, "")
        XCTAssertEqual(store.githubTokenPersistenceState, .empty)
        XCTAssertEqual(store.jiraTokenPersistenceState, .empty)
    }

    func testLaunchAtLoginRequiresApprovalSurfacesWarningState() {
        let suiteName = "BugNarrator-SettingsLaunchAtLoginApprovalTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let launchAtLoginService = MockLaunchAtLoginService(status: .requiresApproval)
        let store = SettingsStore(
            defaults: defaults,
            keychainService: MockKeychainService(),
            launchAtLoginService: launchAtLoginService
        )

        XCTAssertTrue(store.openAtStartup)
        XCTAssertEqual(store.openAtStartupStatusTone, .warning)
        XCTAssertEqual(
            store.openAtStartupStatusMessage,
            "BugNarrator is enabled to open at login, but macOS still requires approval in System Settings > General > Login Items."
        )
    }

    func testLaunchAtLoginNotFoundKeepsToggleAvailableForRegistrationRetry() {
        let suiteName = "BugNarrator-SettingsLaunchAtLoginNotFoundTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let launchAtLoginService = MockLaunchAtLoginService(status: .notFound)
        let store = SettingsStore(
            defaults: defaults,
            keychainService: MockKeychainService(),
            launchAtLoginService: launchAtLoginService
        )

        XCTAssertFalse(store.openAtStartup)
        XCTAssertTrue(store.openAtStartupSupported)
        XCTAssertTrue(store.openAtStartupControlIsEnabled)
        XCTAssertEqual(store.openAtStartupStatusTone, .warning)
        XCTAssertEqual(
            store.openAtStartupStatusMessage,
            "Open at Startup is not registered with macOS yet. Turn it on to register BugNarrator as a Login Item."
        )
    }

    func testLaunchAtLoginUnavailableDisablesStartupControl() {
        let suiteName = "BugNarrator-SettingsLaunchAtLoginUnavailableTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let launchAtLoginService = MockLaunchAtLoginService(status: .unavailable)
        let store = SettingsStore(
            defaults: defaults,
            keychainService: MockKeychainService(),
            launchAtLoginService: launchAtLoginService
        )

        XCTAssertFalse(store.openAtStartup)
        XCTAssertFalse(store.openAtStartupSupported)
        XCTAssertFalse(store.openAtStartupControlIsEnabled)
        XCTAssertEqual(store.openAtStartupStatusTone, .warning)
        XCTAssertEqual(
            store.openAtStartupStatusMessage,
            "Open at Startup is unavailable for this app copy. Install BugNarrator in Applications and use a signed build if you want BugNarrator to launch automatically."
        )
    }

    func testLaunchAtLoginFailureRestoresActualStateAndShowsError() {
        let suiteName = "BugNarrator-SettingsLaunchAtLoginFailureTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let launchAtLoginService = MockLaunchAtLoginService()
        launchAtLoginService.setEnabledError = NSError(
            domain: "LaunchAtLoginTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The login item could not be registered."]
        )
        let store = SettingsStore(
            defaults: defaults,
            keychainService: MockKeychainService(),
            launchAtLoginService: launchAtLoginService
        )

        store.openAtStartup = true

        XCTAssertFalse(store.openAtStartup)
        XCTAssertEqual(store.openAtStartupStatusTone, .error)
        XCTAssertEqual(
            store.openAtStartupStatusMessage,
            "BugNarrator couldn't update the Open at Startup setting. The login item could not be registered."
        )
    }

    func testLaunchAtLoginFailurePreservesStatusMessageWhenServiceProvidesOne() {
        let suiteName = "BugNarrator-SettingsLaunchAtLoginFailureStatusTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let launchAtLoginService = MockLaunchAtLoginService(status: .requiresApproval)
        launchAtLoginService.setEnabledError = NSError(
            domain: "LaunchAtLoginTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "The login item could not be updated."]
        )
        let store = SettingsStore(
            defaults: defaults,
            keychainService: MockKeychainService(),
            launchAtLoginService: launchAtLoginService
        )

        store.openAtStartup = false

        XCTAssertTrue(store.openAtStartup)
        XCTAssertEqual(store.openAtStartupStatusTone, .error)
        XCTAssertEqual(
            store.openAtStartupStatusMessage,
            "BugNarrator is enabled to open at login, but macOS still requires approval in System Settings > General > Login Items. Details: The login item could not be updated."
        )
    }

    func testProviderFallbackBaseURLsCoverEveryAIProviderCase() {
        for provider in AIProvider.allCases {
            XCTAssertNotNil(
                SettingsStore.providerFallbackBaseURLs[provider],
                "Missing fallback URL for AIProvider.\(provider.rawValue); update SettingsStore.providerFallbackBaseURLs."
            )
        }
        XCTAssertEqual(
            SettingsStore.providerFallbackBaseURLs.count,
            AIProvider.allCases.count,
            "providerFallbackBaseURLs must contain exactly one entry per AIProvider case."
        )
    }

    func testFallbackBaseURLReturnsParseableURLForEveryProvider() {
        for provider in AIProvider.allCases {
            let url = SettingsStore.fallbackBaseURL(for: provider)
            XCTAssertFalse(url.absoluteString.isEmpty, "fallbackBaseURL produced an empty URL for \(provider.rawValue).")
            XCTAssertNotNil(url.host, "fallbackBaseURL for \(provider.rawValue) has no host: \(url.absoluteString).")
        }
    }
}
