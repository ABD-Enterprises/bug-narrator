import Foundation

/// Result of a stale-aggregate-device cleanup scan, extracted from
/// `SystemAudioRecorder` (#435 slice 435a).
struct SystemAudioAggregateDeviceCleanupSummary: Equatable {
    var inspectedCount = 0
    var destroyedCount = 0
    var failedCount = 0
    var scanFailed = false
}

/// Identity of the CoreAudio aggregate device BugNarrator creates for
/// system-audio capture, extracted from `SystemAudioRecorder` (#435 slice
/// 435a).
///
/// Pure string logic — no CoreAudio calls, no permission prompts. The `uidPrefix`
/// is how BugNarrator recognizes aggregate devices it owns during cleanup, so it
/// is the ownership contract and is frozen by tests.
enum SystemAudioAggregateDeviceIdentity {
    static let name = "BugNarrator System Audio"
    static let uidPrefix = "BugNarrator.SystemAudio."

    static func makeUID() -> String {
        "\(uidPrefix)\(UUID().uuidString)"
    }

    static func isOwnedAggregateDeviceUID(_ uid: String) -> Bool {
        uid.hasPrefix(uidPrefix)
    }
}
