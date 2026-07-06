import Foundation

/// A lazy source of stored sessions for export. The exporter pulls sessions one
/// at a time via `forEach`, so the whole library never has to be materialized in
/// memory simultaneously (#508). `count` is the number of sessions `forEach` will
/// yield, known up front from the lightweight library index.
struct PrivacyDataSessionStream {
    let count: Int
    let forEach: (_ body: (TranscriptSession) throws -> Void) throws -> Void

    /// Convenience for callers (and tests) that already hold a materialized array.
    init(sessions: [TranscriptSession]) {
        count = sessions.count
        forEach = { body in
            for session in sessions {
                try body(session)
            }
        }
    }

    init(count: Int, forEach: @escaping (_ body: (TranscriptSession) throws -> Void) throws -> Void) {
        self.count = count
        self.forEach = forEach
    }
}
