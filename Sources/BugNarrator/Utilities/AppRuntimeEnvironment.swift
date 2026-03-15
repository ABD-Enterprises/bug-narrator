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

    var shouldBypassSingleInstanceEnforcement: Bool {
        isRunningUnderTests
    }
}
