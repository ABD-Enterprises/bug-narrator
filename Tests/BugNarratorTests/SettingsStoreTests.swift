import AppKit
import XCTest
@testable import BugNarrator

final class SettingsStoreTests: XCTestCase {
    func testSettingsPersistAcrossReloads() {
        let suiteName = "BugNarrator-SettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = MockKeychainService()
        let firstStore = SettingsStore(defaults: defaults, keychainService: keychain)
        firstStore.apiKey = "persisted-api-key"
        firstStore.preferredModel = "whisper-1"
        firstStore.languageHint = "en"
        firstStore.transcriptionPrompt = "Focus on bugs."
        firstStore.issueExtractionModel = "gpt-4.1-mini"
        firstStore.autoCopyTranscript = false
        firstStore.autoSaveTranscript = false
        firstStore.autoExtractIssues = true
        firstStore.debugMode = true
        firstStore.startRecordingHotkeyShortcut = HotkeyShortcut(
            keyCode: 1,
            modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue
        )
        firstStore.stopRecordingHotkeyShortcut = HotkeyShortcut(
            keyCode: 3,
            modifiers: NSEvent.ModifierFlags.command.union(.option).rawValue
        )
        firstStore.markerHotkeyShortcut = HotkeyAction.insertMarker.defaultShortcut
        firstStore.screenshotHotkeyShortcut = HotkeyAction.captureScreenshot.defaultShortcut
        firstStore.githubToken = "github-token"
        firstStore.githubRepositoryOwner = "acme"
        firstStore.githubRepositoryName = "bugnarrator"
        firstStore.githubDefaultLabels = "bug,triage"
        firstStore.jiraBaseURL = "acme.atlassian.net"
        firstStore.jiraEmail = "you@example.com"
        firstStore.jiraAPIToken = "jira-token"
        firstStore.jiraProjectKey = "FM"
        firstStore.jiraIssueType = "Task"

        let secondStore = SettingsStore(defaults: defaults, keychainService: keychain)

        XCTAssertEqual(secondStore.apiKey, "persisted-api-key")
        XCTAssertEqual(secondStore.preferredModel, "whisper-1")
        XCTAssertEqual(secondStore.languageHint, "en")
        XCTAssertEqual(secondStore.transcriptionPrompt, "Focus on bugs.")
        XCTAssertEqual(secondStore.issueExtractionModel, "gpt-4.1-mini")
        XCTAssertFalse(secondStore.autoCopyTranscript)
        XCTAssertFalse(secondStore.autoSaveTranscript)
        XCTAssertTrue(secondStore.autoExtractIssues)
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
        XCTAssertEqual(secondStore.githubToken, "github-token")
        XCTAssertEqual(secondStore.githubRepositoryOwner, "acme")
        XCTAssertEqual(secondStore.githubRepositoryName, "bugnarrator")
        XCTAssertEqual(secondStore.githubDefaultLabelsList, ["bug", "triage"])
        XCTAssertEqual(secondStore.jiraBaseURL, "acme.atlassian.net")
        XCTAssertEqual(secondStore.jiraEmail, "you@example.com")
        XCTAssertEqual(secondStore.jiraAPIToken, "jira-token")
        XCTAssertEqual(secondStore.jiraProjectKey, "FM")
        XCTAssertEqual(secondStore.jiraIssueType, "Task")
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
        XCTAssertEqual(store.apiKeyPersistenceState, .keychain)
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
        store.apiKey = "sk-test-secret-1234"

        XCTAssertEqual(store.maskedAPIKey, "••••••••1234")
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

    func testDuplicateHotkeyAssignmentsDisableOlderConflictingAction() {
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

        XCTAssertEqual(store.stopRecordingHotkeyShortcut, duplicateShortcut)
        XCTAssertEqual(store.startRecordingHotkeyShortcut, .disabled)
    }

    func testSettingsLoadLegacyKeychainServiceAndMigrateToBugNarratorNamespace() {
        let suiteName = "BugNarrator-SettingsLegacyKeychainTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let keychain = MockKeychainService()
        keychain.values["SessionMic.OpenAI::openai-api-key"] = "legacy-api-key"

        let store = SettingsStore(defaults: defaults, keychainService: keychain)

        XCTAssertEqual(store.apiKey, "legacy-api-key")
        XCTAssertEqual(
            keychain.values["BugNarrator.OpenAI::openai-api-key"],
            "legacy-api-key"
        )
        XCTAssertNil(keychain.values["SessionMic.OpenAI::openai-api-key"])
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
        XCTAssertTrue(
            keychain.readRequests.contains {
                $0.service == "SessionMic.OpenAI" && !$0.allowInteraction
            }
        )
        XCTAssertNil(keychain.values["BugNarrator.OpenAI::openai-api-key"])

        store.refreshOpenAISecretForUserInitiatedAccess()

        XCTAssertEqual(store.apiKey, "legacy-api-key")
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
        keychain.values[legacyGitHubKey] = "legacy-github-token"
        keychain.values[legacyJiraKey] = "legacy-jira-token"
        keychain.interactionRequiredKeys = [legacyGitHubKey, legacyJiraKey]

        let store = SettingsStore(defaults: defaults, keychainService: keychain)

        XCTAssertEqual(store.githubToken, "")
        XCTAssertEqual(store.jiraAPIToken, "")
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

        XCTAssertEqual(store.githubToken, "legacy-github-token")
        XCTAssertEqual(store.jiraAPIToken, "legacy-jira-token")
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
            "legacy-github-token"
        )
        XCTAssertEqual(
            keychain.values["BugNarrator.Jira::jira-api-token"],
            "legacy-jira-token"
        )
    }

    func testMaskedExportTokensOnlyExposeSuffix() {
        let suiteName = "BugNarrator-SettingsExportMaskTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())
        store.githubToken = "github-secret-9876"
        store.jiraAPIToken = "jira-secret-4321"

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
}
