import CoreGraphics

enum MenuBarStatusRecoveryAction: Equatable {
    case none
    case microphone
    case screenRecording
    case openAI
    case exportConfiguration
    case storage
}

struct MenuBarStatusPresentation: Equatable {
    let preferredWidth: CGFloat
    let recoveryAction: MenuBarStatusRecoveryAction

    init(status: AppStatus, currentError: AppError?) {
        self.recoveryAction = Self.recoveryAction(for: currentError)
        self.preferredWidth = Self.preferredWidth(for: status, currentError: currentError)
    }

    private static func recoveryAction(for currentError: AppError?) -> MenuBarStatusRecoveryAction {
        switch currentError {
        case .microphonePermissionDenied, .microphonePermissionRestricted, .microphoneUnavailable:
            return .microphone
        case .screenRecordingPermissionDenied:
            return .screenRecording
        case .missingAPIKey, .invalidAPIKey, .revokedAPIKey:
            return .openAI
        case .exportConfigurationMissing:
            return .exportConfiguration
        case .storageFailure:
            return .storage
        default:
            return .none
        }
    }

    private static func preferredWidth(for status: AppStatus, currentError: AppError?) -> CGFloat {
        if recoveryAction(for: currentError) != .none {
            return 420
        }

        if let detail = status.detail, detail.count > 85 || status.phase == .transcribing {
            return 390
        }

        return 340
    }
}
