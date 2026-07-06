import CoreMedia
import Foundation

struct MixedAudioSourceStartTimes {
    let microphoneStartedAt: TimeInterval
    let systemAudioStartedAt: TimeInterval

    var insertionOffsets: MixedAudioTrackInsertionOffsets {
        MixedAudioTrackInsertionOffsets(
            microphoneStartedAt: microphoneStartedAt,
            systemAudioStartedAt: systemAudioStartedAt
        )
    }
}
