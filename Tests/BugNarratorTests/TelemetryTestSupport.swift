import Foundation
@testable import BugNarrator

final class MockOperationalTelemetryRecorder: OperationalTelemetryRecording {
    private(set) var recordedEvents: [(name: String, metadata: [String: String])] = []
    var recentEventsResult: [OperationalTelemetryEvent] = []
    private(set) var recentEventsLimits: [Int] = []
    private(set) var clearCallCount = 0
    var clearError: Error?

    func record(_ name: String, metadata: [String: String] = [:]) {
        recordedEvents.append((name: name, metadata: metadata))
    }

    func recentEvents(limit: Int) -> [OperationalTelemetryEvent] {
        recentEventsLimits.append(limit)
        return Array(recentEventsResult.suffix(limit))
    }

    func clear() throws {
        clearCallCount += 1
        if let clearError {
            throw clearError
        }
    }
}
