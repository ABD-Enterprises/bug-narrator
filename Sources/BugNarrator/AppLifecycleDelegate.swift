import AppKit

final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    static var appState: AppState?
    @MainActor
    static var launchContinuityMonitor: LaunchContinuityMonitor?

    @MainActor
    private lazy var termination = AppTerminationCoordinator(
        shouldTerminate: { Self.appState?.applicationShouldTerminate() ?? .terminateNow },
        shutdown: { await LocalTranscriptionManager.shared.shutdown() }
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
    private var pending: Task<Void, Never>?

    init(shouldTerminate: @escaping () -> NSApplication.TerminateReply,
         shutdown: @escaping () async -> Void) {
        self.shouldTerminate = shouldTerminate
        self.shutdown = shutdown
    }

    func request(reply: @escaping (Bool) -> Void) -> NSApplication.TerminateReply {
        guard pending == nil else { return .terminateLater }
        let decision = shouldTerminate()
        guard decision == .terminateNow else { return decision }
        pending = Task {
            await shutdown()
            // A recording action may have arrived while server cleanup was pending.
            let allowed = shouldTerminate() == .terminateNow
            pending = nil
            reply(allowed)
        }
        return .terminateLater
    }
}
