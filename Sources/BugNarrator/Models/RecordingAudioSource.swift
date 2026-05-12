import Foundation

enum RecordingAudioSource: String, CaseIterable, Identifiable {
    case microphone
    case systemAudio
    case microphoneAndSystemAudio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone:
            return "Mic only"
        case .systemAudio:
            return "System audio only"
        case .microphoneAndSystemAudio:
            return "Mic + system audio"
        }
    }

    var diagnosticsValue: String {
        rawValue
    }

    var usesMicrophone: Bool {
        switch self {
        case .microphone, .microphoneAndSystemAudio:
            return true
        case .systemAudio:
            return false
        }
    }

    var usesSystemAudio: Bool {
        switch self {
        case .systemAudio, .microphoneAndSystemAudio:
            return true
        case .microphone:
            return false
        }
    }
}
