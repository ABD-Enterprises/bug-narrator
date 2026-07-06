@preconcurrency import AVFoundation
import Foundation

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
