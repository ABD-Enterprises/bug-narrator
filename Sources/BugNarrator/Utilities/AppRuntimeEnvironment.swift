import Foundation

struct AppRuntimeEnvironment: Equatable {
    let bundlePath: String
    let environment: [String: String]

    init(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.bundlePath = bundle.bundleURL.path
        self.environment = environment
    }

    init(bundlePath: String, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.bundlePath = bundlePath
        self.environment = environment
    }

    var isLocalTestingBuild: Bool {
        let normalizedPath = bundlePath.lowercased()

        return (normalizedPath.contains("deriveddata") && normalizedPath.contains("/products/"))
            || normalizedPath.contains("/build/deriveddata/build/products/")
    }

    var isRunningUnderTests: Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }

    var isRunningSettingsUISmokeTest: Bool {
        environment["BUGNARRATOR_SETTINGS_UI_SMOKE_TEST"] == "1"
    }

    var isRunningBugNarratorUITest: Bool {
        isRunningSettingsUISmokeTest || environment["BUGNARRATOR_UI_TEST_MODE"] == "1"
    }

    var usesIsolatedRuntime: Bool {
        isRunningUnderTests || isRunningBugNarratorUITest
    }

    var shouldBypassSingleInstanceEnforcement: Bool {
        usesIsolatedRuntime
    }

    var shouldOpenSettingsOnLaunch: Bool {
        environment["BUGNARRATOR_OPEN_SETTINGS_ON_LAUNCH"] == "1"
    }

    var shouldOpenSessionLibraryOnLaunch: Bool {
        environment["BUGNARRATOR_OPEN_SESSION_LIBRARY_ON_LAUNCH"] == "1"
    }

    var shouldOpenRecordingControlsOnLaunch: Bool {
        environment["BUGNARRATOR_OPEN_RECORDING_CONTROLS_ON_LAUNCH"] == "1"
    }

    var shouldSeedSessionLibraryUITestData: Bool {
        environment["BUGNARRATOR_SEED_SESSION_LIBRARY_UI_TEST_DATA"] == "1"
    }

    var shouldUseDeterministicUITestServices: Bool {
        environment["BUGNARRATOR_UI_TEST_SAFE_SERVICES"] == "1"
    }

    var testIsolationScope: String {
        let rawScope = environment["XCTestSessionIdentifier"]
            ?? environment["XCTestConfigurationFilePath"]
            ?? environment["BUGNARRATOR_SETTINGS_UI_SMOKE_SCOPE"]
            ?? ProcessInfo.processInfo.globallyUniqueString

        return rawScope.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]+"#,
            with: "-",
            options: .regularExpression
        )
    }

    /// Lets a UI test pin the provider, the way BUGNARRATOR_TEST_LAUNCH_AT_LOGIN_STATUS
    /// pins launch-at-login. Only consulted on the isolated-runtime path in
    /// AppBootstrap, so it cannot influence a production launch (#1026).
    /// Under a deterministic UI-test runtime the local-server reachability probe
    /// must NOT open a real socket: the suite would then pass on a machine running
    /// Parakeet and fail in CI, which is exactly the false green that #1026 already
    /// produced once in the unit suite. Defaults to reachable so the ordinary UI
    /// path is exercisable; a test that is ABOUT the unreachable state sets "0".
    var testLocalServerIsReachable: Bool? {
        guard usesIsolatedRuntime else { return nil }
        if let raw = environment["BUGNARRATOR_TEST_LOCAL_SERVER_REACHABLE"] {
            return raw == "1"
        }
        return shouldUseDeterministicUITestServices ? true : nil
    }

    var testAIProvider: AIProvider? {
        // Self-guarding on purpose. AppBootstrap only reads this inside the
        // isolated-runtime branch today, but that safety is a property of the
        // CALL SITE, not of this value — move the read and the guard disappears.
        // Unknown values return nil via the enum, so a typo is ignored rather
        // than silently selecting some other provider.
        guard usesIsolatedRuntime else { return nil }
        guard let raw = environment["BUGNARRATOR_TEST_AI_PROVIDER"] else { return nil }
        return AIProvider(rawValue: raw)
    }

    var testLaunchAtLoginStatus: LaunchAtLoginStatus {
        switch environment["BUGNARRATOR_TEST_LAUNCH_AT_LOGIN_STATUS"] {
        case "enabled":
            return .enabled
        case "requires_approval":
            return .requiresApproval
        case "not_found":
            return .notFound
        case "unavailable":
            return .unavailable
        default:
            return .disabled
        }
    }
}
