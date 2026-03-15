import Foundation

enum AppStatus: Equatable {
    case idle(String? = nil)
    case recording(String? = nil)
    case transcribing(String? = nil)
    case success(String)
    case error(String)

    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case success
        case error
    }

    var phase: Phase {
        switch self {
        case .idle:
            return .idle
        case .recording:
            return .recording
        case .transcribing:
            return .transcribing
        case .success:
            return .success
        case .error:
            return .error
        }
    }

    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .recording:
            return "Recording"
        case .transcribing:
            return "Transcribing"
        case .success:
            return "Success"
        case .error:
            return "Error"
        }
    }

    var detail: String? {
        switch self {
        case .idle(let message), .recording(let message), .transcribing(let message):
            return message
        case .success(let message), .error(let message):
            return message
        }
    }
}
