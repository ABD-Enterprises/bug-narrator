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

struct MixedAudioTrackInsertionOffsets: Equatable {
    static let zero = MixedAudioTrackInsertionOffsets(
        microphoneOffset: 0,
        systemAudioOffset: 0
    )

    let microphoneOffset: TimeInterval
    let systemAudioOffset: TimeInterval

    init(microphoneStartedAt: TimeInterval, systemAudioStartedAt: TimeInterval) {
        let earliestStart = min(microphoneStartedAt, systemAudioStartedAt)
        microphoneOffset = max(0, microphoneStartedAt - earliestStart)
        systemAudioOffset = max(0, systemAudioStartedAt - earliestStart)
    }

    private init(microphoneOffset: TimeInterval, systemAudioOffset: TimeInterval) {
        self.microphoneOffset = microphoneOffset
        self.systemAudioOffset = systemAudioOffset
    }

    var microphoneInsertionTime: CMTime {
        CMTime(seconds: microphoneOffset, preferredTimescale: 1_000_000)
    }

    var systemAudioInsertionTime: CMTime {
        CMTime(seconds: systemAudioOffset, preferredTimescale: 1_000_000)
    }
}
