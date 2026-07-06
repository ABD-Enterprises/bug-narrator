import AppKit

final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    static var appState: AppState?
    @MainActor
    static var launchContinuityMonitor: LaunchContinuityMonitor?

    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.appState?.applicationShouldTerminate() ?? .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.launchContinuityMonitor?.markGracefulTermination()
    }
}
