import XCTest
@testable import BugNarrator

final class SingleInstanceControllerTests: XCTestCase {
    func testLaunchDispositionIsPrimaryWhenNoOtherInstanceMatchesBundleIdentifier() {
        let disposition = SingleInstanceController.launchDisposition(
            bundleIdentifier: "com.abdenterprises.bugnarrator",
            currentProcessIdentifier: 101,
            runningApplications: [
                RunningApplicationSnapshot(processIdentifier: 101, bundleIdentifier: "com.abdenterprises.bugnarrator"),
                RunningApplicationSnapshot(processIdentifier: 202, bundleIdentifier: "com.example.other")
            ]
        )

        XCTAssertEqual(disposition, .primary)
    }

    func testLaunchDispositionRejectsSecondInstanceWhenAnotherProcessSharesBundleIdentifier() {
        let disposition = SingleInstanceController.launchDisposition(
            bundleIdentifier: "com.abdenterprises.bugnarrator",
            currentProcessIdentifier: 404,
            runningApplications: [
                RunningApplicationSnapshot(processIdentifier: 120, bundleIdentifier: "com.abdenterprises.bugnarrator"),
                RunningApplicationSnapshot(processIdentifier: 404, bundleIdentifier: "com.abdenterprises.bugnarrator")
            ]
        )

        XCTAssertEqual(disposition, .secondary(existingProcessIdentifier: 120))
    }

    func testLaunchDispositionUsesLowestExistingProcessIdentifierWhenMultipleInstancesAreVisible() {
        let disposition = SingleInstanceController.launchDisposition(
            bundleIdentifier: "com.abdenterprises.bugnarrator",
            currentProcessIdentifier: 999,
            runningApplications: [
                RunningApplicationSnapshot(processIdentifier: 420, bundleIdentifier: "com.abdenterprises.bugnarrator"),
                RunningApplicationSnapshot(processIdentifier: 210, bundleIdentifier: "com.abdenterprises.bugnarrator"),
                RunningApplicationSnapshot(processIdentifier: 999, bundleIdentifier: "com.abdenterprises.bugnarrator")
            ]
        )

        XCTAssertEqual(disposition, .secondary(existingProcessIdentifier: 210))
    }
}
