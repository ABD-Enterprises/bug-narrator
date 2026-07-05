@preconcurrency import AVFoundation
import Foundation

struct RecordedAudio {
    let fileURL: URL
    let duration: TimeInterval
}

@MainActor
protocol AudioRecorderEngine: AnyObject {
    var delegate: (any AVAudioRecorderDelegate)? { get set }
    var currentTime: TimeInterval { get }

    func prepareToRecord() -> Bool
    func record() -> Bool
    func stop()
}

extension AVAudioRecorder: AudioRecorderEngine {}

typealias AudioRecorderEngineFactory = (URL, [String: Any]) throws -> any AudioRecorderEngine

enum AudioRecorderCaptureFormat: Equatable {
    case aacM4A
    case wavPCM

    var fileExtension: String {
        switch self {
        case .aacM4A:
            return "m4a"
        case .wavPCM:
            return "wav"
        }
    }

    var recordingSettings: [String: Any] {
        switch self {
        case .aacM4A:
            return [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
        case .wavPCM:
            return [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        }
    }
}

