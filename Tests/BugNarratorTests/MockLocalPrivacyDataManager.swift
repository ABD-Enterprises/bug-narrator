import Foundation
@testable import BugNarrator

final class MockLocalPrivacyDataManager: LocalPrivacyDataManaging {
    private(set) var clearCallCount = 0

    func clearLocalSupportArtifacts() async {
        clearCallCount += 1
    }
}

