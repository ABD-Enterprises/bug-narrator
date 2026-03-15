import Foundation

struct AppRuntimeEnvironment: Equatable {
    let bundlePath: String

    init(bundle: Bundle = .main) {
        self.bundlePath = bundle.bundleURL.path
    }

    init(bundlePath: String) {
        self.bundlePath = bundlePath
    }

    var isLocalTestingBuild: Bool {
        let normalizedPath = bundlePath.lowercased()

        return (normalizedPath.contains("deriveddata") && normalizedPath.contains("/products/"))
            || normalizedPath.contains("/build/deriveddata/build/products/")
    }
}
