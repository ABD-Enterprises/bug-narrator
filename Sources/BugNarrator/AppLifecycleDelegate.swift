import AppKit

final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    static var appState: AppState?
    @MainActor
    static var launchContinuityMonitor: LaunchContinuityMonitor?

    @MainActor
    private lazy var termination = AppTerminationCoordinator(
        shouldTerminate: { Self.appState?.applicationShouldTerminate() ?? .terminateNow },
        shutdown: { await Self.appState?.localTranscriptionManager.shutdown() },
        setTerminationPending: { Self.appState?.setTerminationPending($0) }
    )

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        termination.request { sender.reply(toApplicationShouldTerminate: $0) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.launchContinuityMonitor?.markGracefulTermination()
    }
}

/// Keep recording/transcription vetoes synchronous; defer only the final OS reply.
@MainActor
final class AppTerminationCoordinator {
    private let shouldTerminate: () -> NSApplication.TerminateReply
    private let shutdown: () async -> Void
    private let setTerminationPending: (Bool) -> Void
    private var pending: Task<Void, Never>?

    init(shouldTerminate: @escaping () -> NSApplication.TerminateReply,
         shutdown: @escaping () async -> Void,
         setTerminationPending: @escaping (Bool) -> Void = { _ in }) {
        self.shouldTerminate = shouldTerminate
        self.shutdown = shutdown
        self.setTerminationPending = setTerminationPending
    }

    func request(reply: @escaping (Bool) -> Void) -> NSApplication.TerminateReply {
        guard pending == nil else { return .terminateLater }
        let decision = shouldTerminate()
        guard decision == .terminateNow else { return decision }
        setTerminationPending(true)
        pending = Task {
            await shutdown()
            // Recheck other eligibility changes while holding recording admission closed.
            let allowed = shouldTerminate() == .terminateNow
            pending = nil
            if !allowed { setTerminationPending(false) }
            reply(allowed)
        }
        return .terminateLater
    }
}
