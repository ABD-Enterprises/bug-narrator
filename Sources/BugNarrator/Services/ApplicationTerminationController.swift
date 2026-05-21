import AppKit
import Foundation

@MainActor
final class ApplicationTerminationController {
    private let statusPhase: () -> AppStatus.Phase
    private let activeRecordingSession: () -> RecordingSessionDraft?
    private let isExtractingIssues: () -> Bool
    private let isExporting: () -> Bool
    private let cancelPendingScreenshotSelection: (String) -> Void
    private let showRecordingControls: () -> Void
    private let showToast: (String, TransientToastStyle) -> Void
    private let dismissToast: () -> Void
    private let unregisterHotkeys: () -> Void
    private let stopTimer: (Bool) -> Void
    private let endActivity: () -> Void
    private let terminateApplication: () -> Void
    private let recordingLogger: DiagnosticsLogger
    private let settingsLogger: DiagnosticsLogger

    init(
        statusPhase: @escaping () -> AppStatus.Phase,
        activeRecordingSession: @escaping () -> RecordingSessionDraft?,
        isExtractingIssues: @escaping () -> Bool,
        isExporting: @escaping () -> Bool,
        cancelPendingScreenshotSelection: @escaping (String) -> Void,
        showRecordingControls: @escaping () -> Void,
        showToast: @escaping (String, TransientToastStyle) -> Void,
        dismissToast: @escaping () -> Void,
        unregisterHotkeys: @escaping () -> Void,
        stopTimer: @escaping (Bool) -> Void,
        endActivity: @escaping () -> Void,
        terminateApplication: @escaping () -> Void = { NSApp.terminate(nil) },
        recordingLogger: DiagnosticsLogger = DiagnosticsLogger(category: .recording),
        settingsLogger: DiagnosticsLogger = DiagnosticsLogger(category: .settings)
    ) {
        self.statusPhase = statusPhase
        self.activeRecordingSession = activeRecordingSession
        self.isExtractingIssues = isExtractingIssues
        self.isExporting = isExporting
        self.cancelPendingScreenshotSelection = cancelPendingScreenshotSelection
        self.showRecordingControls = showRecordingControls
        self.showToast = showToast
        self.dismissToast = dismissToast
        self.unregisterHotkeys = unregisterHotkeys
        self.stopTimer = stopTimer
        self.endActivity = endActivity
        self.terminateApplication = terminateApplication
        self.recordingLogger = recordingLogger
        self.settingsLogger = settingsLogger
    }

    func requestApplicationTermination() {
        guard applicationShouldTerminate() == .terminateNow else {
            return
        }

        terminateApplication()
    }

    func applicationShouldTerminate() -> NSApplication.TerminateReply {
        guard statusPhase() == .recording,
              let activeRecordingSession = activeRecordingSession() else {
            return .terminateNow
        }

        recordingLogger.warning(
            "termination_blocked_while_recording",
            "BugNarrator blocked an app termination request while a recording session was still active.",
            metadata: ["session_id": activeRecordingSession.sessionID.uuidString]
        )
        cancelPendingScreenshotSelection("Quit was requested while recording, so pending screenshot selection was cancelled.")
        showRecordingControls()
        showToast("Stop recording before quitting BugNarrator.", .informational)
        return .terminateCancel
    }

    func prepareForApplicationTermination() {
        let recordingSession = activeRecordingSession()
        settingsLogger.info(
            "application_will_terminate",
            "BugNarrator is preparing for application shutdown.",
            metadata: [
                "status_phase": statusPhase().debugName,
                "has_active_recording_session": recordingSession == nil ? "no" : "yes",
                "is_extracting_issues": isExtractingIssues() ? "yes" : "no",
                "is_exporting": isExporting() ? "yes" : "no"
            ]
        )

        if let recordingSession {
            recordingLogger.warning(
                "application_terminating_during_recording",
                "BugNarrator is terminating while a recording session is still active.",
                metadata: ["session_id": recordingSession.sessionID.uuidString]
            )
        }

        dismissToast()
        unregisterHotkeys()
        stopTimer(false)
        endActivity()
    }
}

private extension AppStatus.Phase {
    var debugName: String {
        switch self {
        case .idle:
            return "idle"
        case .recording:
            return "recording"
        case .transcribing:
            return "transcribing"
        case .success:
            return "success"
        case .error:
            return "error"
        }
    }
}
