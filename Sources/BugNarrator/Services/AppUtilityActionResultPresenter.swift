import AppKit
import Foundation

@MainActor
final class AppUtilityActionResultPresenter {
    private let statusPhase: () -> AppStatus.Phase
    private let setStatus: (AppStatus) -> Void
    private let logger: DiagnosticsLogger

    init(
        statusPhase: @escaping () -> AppStatus.Phase,
        setStatus: @escaping (AppStatus) -> Void,
        logger: DiagnosticsLogger = DiagnosticsLogger(category: .settings)
    ) {
        self.statusPhase = statusPhase
        self.setStatus = setStatus
        self.logger = logger
    }

    func present(_ result: AppUtilityActionResult) {
        guard case .failed(let message) = result else {
            return
        }

        presentFailure(message)
    }

    func present(_ result: PermissionSettingsOpenResult) {
        guard case .failed(let message) = result else {
            return
        }

        presentFailure(message)
    }

    func presentFailure(_ message: String) {
        logger.warning("utility_action_failed", message)
        setStatus(Self.failureStatus(message: message, statusPhase: statusPhase()))
    }

    static func failureStatus(message: String, statusPhase: AppStatus.Phase) -> AppStatus {
        switch statusPhase {
        case .recording:
            return .recording("\(message) Recording is still active.")
        case .transcribing:
            return .transcribing("\(message) Background work is still in progress.")
        case .idle, .success, .error:
            return .error(message)
        }
    }
