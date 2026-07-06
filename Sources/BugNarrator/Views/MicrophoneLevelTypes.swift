import AVFoundation

enum MicrophoneInputLevelState: Equatable {
    case idle
    case monitoring
    case permissionNeeded
    case unavailable

    var label: String {
        switch self {
        case .idle:
            return "Paused"
        case .monitoring:
            return "Live"
        case .permissionNeeded:
            return "Permission needed"
        case .unavailable:
            return "Unavailable"
        }
    }

    func accessibilityValue(level: Float) -> String {
        switch self {
        case .monitoring:
            return "\(Int((level * 100).rounded())) percent"
        case .permissionNeeded:
            return "Microphone permission is needed"
        case .unavailable:
            return "Microphone level is unavailable"
        case .idle:
            return "Paused"
        }
    }
}

enum MicrophoneLevelCalculator {
    static func normalizedRMSLevel(for buffer: AVAudioPCMBuffer) -> Float {
        guard let channels = buffer.floatChannelData else {
            return 0
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else {
            return 0
        }

        var sumOfSquares: Float = 0
        var sampleCount = 0

        for channelIndex in 0..<channelCount {
            let samples = channels[channelIndex]
            for frameIndex in 0..<frameLength {
                let sample = samples[frameIndex]
                sumOfSquares += sample * sample
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else {
            return 0
        }

        let rms = sqrt(sumOfSquares / Float(sampleCount))
        return min(1, max(0, rms * 4))
    }
}

enum MicrophoneInputLevelTapFactory {
    static func makeTap(deliverLevel: @escaping @Sendable (Float) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            deliverLevel(MicrophoneLevelCalculator.normalizedRMSLevel(for: buffer))
        }
    }
}
