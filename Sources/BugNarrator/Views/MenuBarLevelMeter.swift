import AVFoundation
import CoreGraphics
import Combine
import SwiftUI

struct LevelMeterView: View {
    let level: Float

    private let segmentCount = 18

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(0..<segmentCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(index < activeSegmentCount ? segmentColor(for: index) : Color.secondary.opacity(0.18))
                        .frame(width: segmentWidth(totalWidth: proxy.size.width), height: proxy.size.height)
                }
            }
        }
    }

    private var activeSegmentCount: Int {
        min(segmentCount, max(0, Int(ceil(Double(level) * Double(segmentCount)))))
    }

    private func segmentWidth(totalWidth: CGFloat) -> CGFloat {
        max(2, (totalWidth - CGFloat(segmentCount - 1) * 3) / CGFloat(segmentCount))
    }

    private func segmentColor(for index: Int) -> Color {
        let ratio = Double(index + 1) / Double(segmentCount)
        if ratio > 0.78 {
            return .red
        }
        if ratio > 0.55 {
            return .orange
        }
        return .green
    }
}

@MainActor
final class MicrophoneInputLevelMonitor: ObservableObject {
    @Published private(set) var currentLevel: Float = 0
    @Published private(set) var state: MicrophoneInputLevelState = .idle

    private let engine = AVAudioEngine()
    private var isMonitoring = false

    func start() {
        guard !isMonitoring else {
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startEngine()
        case .notDetermined, .denied, .restricted:
            currentLevel = 0
            state = .permissionNeeded
        @unknown default:
            currentLevel = 0
            state = .unavailable
        }
    }

    func stop() {
        guard isMonitoring || state != .idle || currentLevel != 0 else {
            return
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isMonitoring = false
        currentLevel = 0
        state = .idle
    }

    private func startEngine() {
        do {
            let inputNode = engine.inputNode
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(
                onBus: 0,
                bufferSize: 1_024,
                format: nil,
                block: MicrophoneInputLevelTapFactory.makeTap { [weak self] level in
                    Task { @MainActor [weak self] in
                        guard let self, isMonitoring else {
                            return
                        }
                        currentLevel = level
                    }
                }
            )

            try engine.start()
            isMonitoring = true
            state = .monitoring
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            isMonitoring = false
            currentLevel = 0
            state = .unavailable
        }
    }
}

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
