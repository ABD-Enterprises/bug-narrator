import Foundation

struct TranscriptStoreRecoveryEvent: Equatable {
    enum Source: Equatable {
        case backup
        case failed
    }

    let source: Source
    let recoveredSessionCount: Int

    var userMessage: String {
        switch source {
        case .backup:
            return "Session history was recovered from the local backup. \(recoveredSessionCount) session\(recoveredSessionCount == 1 ? "" : "s") restored."
        case .failed:
            return "Session history could not be read from the primary or backup store. A new empty library was opened."
        }
    }
}
