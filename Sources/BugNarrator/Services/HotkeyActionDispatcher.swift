import Combine
import Foundation

@MainActor
final class HotkeyActionDispatcher {
    private let statusPhase: () -> AppStatus.Phase
    private let startRecording: () async -> Void
    private let stopRecording: () async -> Void
    private let captureScreenshot: () async -> Void

    init(
        statusPhase: @escaping () -> AppStatus.Phase,
        startRecording: @escaping () async -> Void,
        stopRecording: @escaping () async -> Void,
        captureScreenshot: @escaping () async -> Void
    ) {
        self.statusPhase = statusPhase
        self.startRecording = startRecording
        self.stopRecording = stopRecording
        self.captureScreenshot = captureScreenshot
    }

    func handle(_ action: HotkeyAction) {
        switch action {
        case .startRecording:
            Task {
                await startRecording()
            }
        case .stopRecording:
            guard statusPhase() == .recording else {
                return
            }
            Task {
                await stopRecording()
            }
        case .captureScreenshot:
            Task {
                await captureScreenshot()
            }
        }
    }
}
