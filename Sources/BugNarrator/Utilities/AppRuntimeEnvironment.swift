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

    var usesIsolatedRuntime: Bool {
        isRunningUnderTests || isRunningSettingsUISmokeTest
    }

    var shouldBypassSingleInstanceEnforcement: Bool {
        usesIsolatedRuntime
    }

    var shouldOpenSettingsOnLaunch: Bool {
        environment["BUGNARRATOR_OPEN_SETTINGS_ON_LAUNCH"] == "1"
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
