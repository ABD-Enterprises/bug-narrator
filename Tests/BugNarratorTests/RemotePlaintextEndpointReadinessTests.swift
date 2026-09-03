import XCTest
@testable import BugNarrator

/// #953: a remote plaintext-HTTP endpoint must fail provider readiness, not
/// merely warn. Warning was the prior behavior and nothing consumed it as a
/// gate, so a single mistyped scheme sent the API key and the recording over
/// the network in the clear.
@MainActor
final class RemotePlaintextEndpointReadinessTests: XCTestCase {
    private func makeStore(provider: AIProvider, baseURL: String) -> SettingsStore {
        let store = makeHermeticSettingsStore(suiteNamePrefix: "BugNarrator-PlaintextReadiness")
        store.aiProvider = provider
        store.openAIBaseURL = baseURL
        return store
    }

    private func makeHermeticSettingsStore(suiteNamePrefix: String) -> SettingsStore {
        let suiteName = "\(suiteNamePrefix)-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        // Capture only the suite NAME here: addTeardownBlock takes a @Sendable
        // closure and UserDefaults is not Sendable, so capturing `defaults`
        // is a data-race error under strict concurrency.
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }

        return SettingsStore(
            defaults: defaults,
            keychainService: MockKeychainService(),
            launchAtLoginService: MockLaunchAtLoginService()
        )
    }

    func testScopedSettingsStoreConstructionsStayCentralized() throws {
        let rootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let expectedSettingsStoreInitCounts = [
            "Tests/BugNarratorTests/PrivacyDataExporterTests.swift": 1,
            "Tests/BugNarratorTests/OnboardingFlowTests.swift": 1,
            "Tests/BugNarratorTests/IssueExportControllerTests.swift": 1,
            "Tests/BugNarratorTests/LocalDataDeletionControllerTests.swift": 1,
            "Tests/BugNarratorTests/PostTranscriptionPipelineControllerTests.swift": 1,
            "Tests/BugNarratorTests/RoutingAudioRecorderTests.swift": 1,
            "Tests/BugNarratorTests/DebugBundleExporterTests.swift": 1,
            "Tests/BugNarratorTests/RemotePlaintextEndpointReadinessTests.swift": 1
        ]

        for (relativePath, expectedCount) in expectedSettingsStoreInitCounts {
            let source = try String(contentsOf: rootURL.appendingPathComponent(relativePath), encoding: .utf8)
            // Substring counting is wrong twice over here. "SettingsStore(" is a
            // substring of `makeHermeticSettingsStore(` and `makeSettingsStore(`,
            // so every HELPER CALL counted as a construction — RoutingAudioRecorder
            // Tests reported 13 for its single real one. It also matched this
            // file's own string literals, so the check counted itself.
            // A preceding-character guard excludes both: an identifier character
            // before the name means it is part of a longer identifier, and a quote
            // means it is a literal.
            let pattern = try NSRegularExpression(pattern: "(?<![A-Za-z0-9_\"])SettingsStore\\(")
            let actualCount = pattern.numberOfMatches(
                in: source,
                range: NSRange(source.startIndex..., in: source)
            )

            XCTAssertEqual(
                actualCount,
                expectedCount,
                "\(relativePath) must keep SettingsStore construction centralized in one hermetic helper."
            )
            XCTAssertTrue(
                source.contains("makeHermeticSettingsStore"),
                "\(relativePath) must construct SettingsStore through makeHermeticSettingsStore."
            )
        }
    }

    // MARK: - Blocked

    func testRemotePlaintextEndpointBlocksReadiness() {
        let store = makeStore(provider: .openAICompatible, baseURL: "http://api.example.com/v1")

        let issue = store.remotePlaintextEndpointIssue
        XCTAssertNotNil(issue, "A remote http:// endpoint must be rejected.")
        XCTAssertEqual(store.aiProviderCompatibilityIssue, issue, "The block must surface as the compatibility issue.")
        XCTAssertFalse(
            store.aiProviderConfigurationIsReady,
            "Readiness is what actually gates recording; a warning nothing reads is not a control."
        )
    }

    /// The message has to name the fix, because the user is looking at a field
    /// they believe is correct.
    func testRejectionMessageNamesTheFixAndTheHost() {
        let store = makeStore(provider: .openAICompatible, baseURL: "http://api.example.com/v1")
        let issue = store.remotePlaintextEndpointIssue ?? ""

        XCTAssertTrue(issue.contains("https://"), issue)
        XCTAssertTrue(issue.contains("api.example.com"), issue)
    }

    func testRemotePlaintextBlocksLocalCompatibleProviderToo() {
        let store = makeStore(provider: .localCompatible, baseURL: "http://models.example.net:1234/v1")
        XCTAssertNotNil(
            store.remotePlaintextEndpointIssue,
            "Choosing the Local-Compatible provider does not make a remote host local."
        )
    }

    /// Security precedence: the plaintext block must win over the ordinary
    /// configuration complaints, or the user fixes the model name and ships
    /// their key in the clear anyway.
    func testPlaintextBlockTakesPrecedenceOverModelCompatibilityIssue() {
        let store = makeStore(provider: .localCompatible, baseURL: "http://models.example.net:1234/v1")
        store.preferredModel = "whisper-1"

        XCTAssertEqual(store.aiProviderCompatibilityIssue, store.remotePlaintextEndpointIssue)
    }

    // MARK: - Still allowed (no regression for local providers)

    func testLoopbackAndPrivateHostsRemainAllowed() {
        for baseURL in [
            "http://localhost:1234/v1",
            "http://127.0.0.1:8422",
            "http://192.168.1.50:1234/v1",
            "http://10.0.0.5:8080/v1",
            "http://172.16.4.4:1234/v1",
            "http://lmstudio:1234/v1",
            "http://nas.local:1234/v1"
        ] {
            let store = makeStore(provider: .localCompatible, baseURL: baseURL)
            XCTAssertNil(
                store.remotePlaintextEndpointIssue,
                "\(baseURL) is the local-provider path this feature must not break."
            )
        }
    }

    func testRemoteHTTPSIsAllowed() {
        let store = makeStore(provider: .openAICompatible, baseURL: "https://api.example.com/v1")
        XCTAssertNil(store.remotePlaintextEndpointIssue)
    }

    /// The shipped defaults are themselves `http://localhost`, so an empty
    /// field must never trip the block.
    func testDefaultsAreNotBlocked() {
        for provider in AIProvider.allCases {
            let store = makeStore(provider: provider, baseURL: "")
            XCTAssertNil(
                store.remotePlaintextEndpointIssue,
                "\(provider.rawValue) default base URL must not be rejected."
            )
        }
    }

    /// Parakeet ignores the typed base URL entirely, so a stale value left in
    /// the field must not block it.
    func testParakeetIsUnaffectedByAStaleTypedBaseURL() {
        let store = makeStore(provider: .parakeetLocal, baseURL: "http://api.example.com/v1")
        XCTAssertNil(store.remotePlaintextEndpointIssue)
    }
}
