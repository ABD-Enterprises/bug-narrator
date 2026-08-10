import Foundation

struct TranscriptStoreRecoveryEvent: Equatable {
    enum Source: Equatable {
        case backup
        case failed
        /// The 500-session retention cap dropped older sessions. Previously
        /// this happened silently and left their screenshots and audio
        /// orphaned on disk with nothing referencing them (#960).
        case retentionEviction
    }

    let source: Source
    let recoveredSessionCount: Int

    var userMessage: String {
        switch source {
        case .backup:
            return "Session history was recovered from the local backup. \(recoveredSessionCount) session\(recoveredSessionCount == 1 ? "" : "s") restored."
        case .failed:
            return "Session history could not be read from the primary or backup store. A new empty library was opened."
        case .retentionEviction:
            let sessionWord = recoveredSessionCount == 1 ? "session" : "sessions"
            return "BugNarrator keeps the 500 most recent sessions. \(recoveredSessionCount) older \(sessionWord), and the screenshots and audio recorded with \(recoveredSessionCount == 1 ? "it" : "them"), were removed to stay within that limit."
        }
    }
}
