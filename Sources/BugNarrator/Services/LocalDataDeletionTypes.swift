import Foundation

struct LocalDataDeletionOutcome: Equatable {
    let deletedSessionCount: Int

    var statusMessage: String {
        if deletedSessionCount == 0 {
            return "Cleared local diagnostics and export history."
        }

        if deletedSessionCount == 1 {
            return "Deleted 1 local session and cleared local diagnostics."
        }

        return "Deleted \(deletedSessionCount) local sessions and cleared local diagnostics."
    }
}

enum LocalDataDeletionResult: Equatable {
    case blocked(message: String)
    case deleted(LocalDataDeletionOutcome)
}

