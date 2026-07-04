import XCTest
@testable import BugNarrator

/// Pure, permission-free coverage of the aggregate-device identity extracted
/// from `SystemAudioRecorder` (#435 slice 435a). The `uidPrefix` is the
/// ownership contract used during stale-device cleanup: a drift here would make
/// BugNarrator either fail to clean up its own aggregate devices or clobber a
/// foreign one, so the literals are frozen.
final class SystemAudioAggregateDeviceTests: XCTestCase {
    func testIdentityConstantsAreExactLiterals() {
        XCTAssertEqual(SystemAudioAggregateDeviceIdentity.name, "BugNarrator System Audio")
        XCTAssertEqual(SystemAudioAggregateDeviceIdentity.uidPrefix, "BugNarrator.SystemAudio.")
    }

    func testMakeUIDStartsWithPrefix() {
        XCTAssertTrue(
            SystemAudioAggregateDeviceIdentity.makeUID()
                .hasPrefix(SystemAudioAggregateDeviceIdentity.uidPrefix)
        )
    }

    func testMakeUIDReturnsUniqueValues() {
        let uids = (0..<100).map { _ in SystemAudioAggregateDeviceIdentity.makeUID() }
        XCTAssertEqual(Set(uids).count, uids.count)
    }

    func testOwnedUIDRoundTrips() {
        let uid = SystemAudioAggregateDeviceIdentity.makeUID()
        XCTAssertTrue(SystemAudioAggregateDeviceIdentity.isOwnedAggregateDeviceUID(uid))
    }

    func testFixedPrefixedUIDIsOwned() {
        XCTAssertTrue(
            SystemAudioAggregateDeviceIdentity.isOwnedAggregateDeviceUID("BugNarrator.SystemAudio.ABC-123")
        )
    }

    func testForeignPrefixIsNotOwned() {
        XCTAssertFalse(SystemAudioAggregateDeviceIdentity.isOwnedAggregateDeviceUID("com.apple.aggregate.42"))
        XCTAssertFalse(SystemAudioAggregateDeviceIdentity.isOwnedAggregateDeviceUID("SomeOtherApp.SystemAudio.1"))
    }

    func testEmptyStringIsNotOwned() {
        XCTAssertFalse(SystemAudioAggregateDeviceIdentity.isOwnedAggregateDeviceUID(""))
    }

    func testPrefixWithoutTrailingDotIsNotOwned() {
        // The trailing dot is part of the prefix; a UID that merely starts with
        // "BugNarrator.SystemAudio" (no dot) must not be treated as owned.
        XCTAssertFalse(SystemAudioAggregateDeviceIdentity.isOwnedAggregateDeviceUID("BugNarrator.SystemAudio"))
    }

    func testCleanupSummaryDefaultsAreZeroAndEquatable() {
        let summary = SystemAudioAggregateDeviceCleanupSummary()
        XCTAssertEqual(summary.inspectedCount, 0)
        XCTAssertEqual(summary.destroyedCount, 0)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertFalse(summary.scanFailed)
        XCTAssertEqual(summary, SystemAudioAggregateDeviceCleanupSummary())

        var mutated = SystemAudioAggregateDeviceCleanupSummary()
        mutated.destroyedCount = 1
        XCTAssertNotEqual(mutated, SystemAudioAggregateDeviceCleanupSummary())
    }
}
