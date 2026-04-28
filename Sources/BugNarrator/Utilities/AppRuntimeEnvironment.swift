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
