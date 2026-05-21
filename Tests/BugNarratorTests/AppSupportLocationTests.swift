import XCTest
@testable import BugNarrator

final class AppSupportLocationTests: XCTestCase {
    func testAppDirectoryFallsBackWhenApplicationSupportURLIsUnavailable() {
        let fileManager = StubApplicationSupportFileManager(applicationSupportURLs: [])

        let appDirectoryURL = AppSupportLocation.appDirectory(fileManager: fileManager)
        defer { try? FileManager.default.removeItem(at: appDirectoryURL.deletingLastPathComponent()) }

        XCTAssertEqual(appDirectoryURL.lastPathComponent, "BugNarrator")
        XCTAssertEqual(appDirectoryURL.deletingLastPathComponent().lastPathComponent, "BugNarrator-ApplicationSupportFallback")
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

    init(applicationSupportURLs: [URL]) {
        self.applicationSupportURLs = applicationSupportURLs
        super.init()
    }

    override func urls(
        for directory: FileManager.SearchPathDirectory,
        in domainMask: FileManager.SearchPathDomainMask
    ) -> [URL] {
        if directory == .applicationSupportDirectory, domainMask == .userDomainMask {
            return applicationSupportURLs
        }

        return super.urls(for: directory, in: domainMask)
    }
}
