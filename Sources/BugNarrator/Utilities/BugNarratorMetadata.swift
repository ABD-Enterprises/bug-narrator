import Foundation

struct BugNarratorMetadata: Equatable {
    static let defaultTagline = "Narrated software testing, turned into actionable issues."
    static let defaultDescription = "BugNarrator helps developers, testers, and product owners narrate software walkthroughs, capture evidence, and turn spoken testing sessions into actionable issues."
    static let defaultCopyright = "© 2026 ABD Enterprises"

    let appName: String
    let tagline: String
    let version: String
    let build: String
    let productDescription: String
    let copyrightLine: String?

    init(
        infoDictionary: [String: Any],
        defaultName: String = "BugNarrator",
        tagline: String = BugNarratorMetadata.defaultTagline,
        productDescription: String = BugNarratorMetadata.defaultDescription
    ) {
        let displayName = (infoDictionary["CFBundleDisplayName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleName = (infoDictionary["CFBundleName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let version = (infoDictionary["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (infoDictionary["CFBundleVersion"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let copyrightLine = (infoDictionary["NSHumanReadableCopyright"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        self.appName = [displayName, bundleName].lazy.compactMap { $0 }.first(where: { !$0.isEmpty }) ?? defaultName
        self.tagline = tagline
        self.version = (version?.isEmpty == false ? version : nil) ?? "1.0"
        self.build = (build?.isEmpty == false ? build : nil) ?? "1"
        self.productDescription = productDescription
        self.copyrightLine = (copyrightLine?.isEmpty == false ? copyrightLine : nil) ?? BugNarratorMetadata.defaultCopyright
    }

    init(bundle: Bundle = .main) {
        self.init(infoDictionary: bundle.infoDictionary ?? [:])
    }

    init() {
        self.init(bundle: .main)
    }

    var versionDescription: String {
        if build == version {
            return "Version \(version)"
        }

        return "Version \(version) (\(build))"
    }
}
