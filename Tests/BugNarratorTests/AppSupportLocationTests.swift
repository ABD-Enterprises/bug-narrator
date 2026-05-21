import XCTest
@testable import BugNarrator

final class AppSupportLocationTests: XCTestCase {
    func testAppDirectoryFallsBackToCachesWhenApplicationSupportURLIsUnavailable() {
        let cachesRoot = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: cachesRoot) }

        let fileManager = StubApplicationSupportFileManager(
            applicationSupportURLs: [],
            cachesURLs: [cachesRoot]
        )

        let appDirectoryURL = AppSupportLocation.appDirectory(fileManager: fileManager)

        XCTAssertEqual(appDirectoryURL.lastPathComponent, "BugNarrator")
        XCTAssertEqual(
            appDirectoryURL.deletingLastPathComponent().lastPathComponent,
            "BugNarrator-ApplicationSupportFallback"
        )
        XCTAssertEqual(
            appDirectoryURL.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL,
            cachesRoot.standardizedFileURL
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: appDirectoryURL.path))
    }

    func testAppDirectoryFallsBackToHomeWhenApplicationSupportAndCachesAreUnavailable() {
        let homeRoot = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: homeRoot) }

        let fileManager = StubApplicationSupportFileManager(
            applicationSupportURLs: [],
            cachesURLs: [],
            homeURL: homeRoot
        )

        let appDirectoryURL = AppSupportLocation.appDirectory(fileManager: fileManager)

        XCTAssertEqual(appDirectoryURL.lastPathComponent, "BugNarrator")
        XCTAssertEqual(
            appDirectoryURL.deletingLastPathComponent().lastPathComponent,
            "BugNarrator-ApplicationSupportFallback"
        )
        XCTAssertEqual(
            appDirectoryURL.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL,
            homeRoot.standardizedFileURL
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: appDirectoryURL.path))
    }

    func testAppDirectoryMigratesLegacyDirectoryWhenApplicationSupportURLIsAvailable() throws {
        let rootDirectoryURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let legacyDirectoryURL = rootDirectoryURL.appendingPathComponent("SessionMic", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectoryURL, withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: legacyDirectoryURL.appendingPathComponent("marker.txt"))

        let fileManager = StubApplicationSupportFileManager(applicationSupportURLs: [rootDirectoryURL])
        let appDirectoryURL = AppSupportLocation.appDirectory(fileManager: fileManager)

        XCTAssertEqual(appDirectoryURL, rootDirectoryURL.appendingPathComponent("BugNarrator", isDirectory: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: appDirectoryURL.appendingPathComponent("marker.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyDirectoryURL.path))
    }

    private func temporaryDirectoryURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class StubApplicationSupportFileManager: FileManager {
    private let applicationSupportURLs: [URL]
    private let cachesURLs: [URL]
    private let homeURL: URL?

    init(
        applicationSupportURLs: [URL],
        cachesURLs: [URL] = [],
        homeURL: URL? = nil
    ) {
        self.applicationSupportURLs = applicationSupportURLs
        self.cachesURLs = cachesURLs
        self.homeURL = homeURL
        super.init()
    }

    override func urls(
        for directory: FileManager.SearchPathDirectory,
        in domainMask: FileManager.SearchPathDomainMask
    ) -> [URL] {
        if directory == .applicationSupportDirectory, domainMask == .userDomainMask {
            return applicationSupportURLs
        }

        if directory == .cachesDirectory, domainMask == .userDomainMask {
            return cachesURLs
        }

        return super.urls(for: directory, in: domainMask)
    }

    override var homeDirectoryForCurrentUser: URL {
        if let homeURL {
            return homeURL
        }

        return super.homeDirectoryForCurrentUser
    }
}
