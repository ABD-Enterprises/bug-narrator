import Foundation
import XCTest
@testable import BugNarrator

final class LaunchContinuityMonitorTests: XCTestCase {
    func testBeginLaunchReturnsNilForFirstLaunchAndReportsUncleanExitForNextLaunch() throws {
        let rootDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-LaunchContinuityMonitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let stateURL = rootDirectoryURL.appendingPathComponent("launch-state.json")
        let monitor = LaunchContinuityMonitor(stateURL: stateURL)
        let firstLaunchDate = Date(timeIntervalSince1970: 100)
        let secondLaunchDate = Date(timeIntervalSince1970: 200)

        XCTAssertNil(monitor.beginLaunch(now: firstLaunchDate))

        let observation = try XCTUnwrap(monitor.beginLaunch(now: secondLaunchDate))
        XCTAssertEqual(observation.previousLaunchStartedAt, firstLaunchDate)
        XCTAssertEqual(observation.detectedAt, secondLaunchDate)
    }

    func testMarkGracefulTerminationClearsLaunchState() throws {
        let rootDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-LaunchContinuityMonitorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let stateURL = rootDirectoryURL.appendingPathComponent("launch-state.json")
        let monitor = LaunchContinuityMonitor(stateURL: stateURL)

        XCTAssertNil(monitor.beginLaunch(now: Date(timeIntervalSince1970: 100)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))

        monitor.markGracefulTermination()

        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
        XCTAssertNil(monitor.beginLaunch(now: Date(timeIntervalSince1970: 200)))
    }
}
