import Foundation
@testable import BugNarrator

final class MockURLHandler: URLOpening {
    private(set) var openedURLs: [URL] = []
    var shouldSucceed = true
    var openResults: [Bool] = []

    @discardableResult
    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        if !openResults.isEmpty {
            return openResults.removeFirst()
        }

        return shouldSucceed
    }
}

