import AppKit
import Combine
import Foundation

@MainActor
final class AppLifecycleNotificationBinder {
    private let notificationCenter: NotificationCenter
    private var cancellables = Set<AnyCancellable>()

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func bind(didBecomeActive: @escaping () -> Void, willTerminate: @escaping () -> Void) {
        cancellables.removeAll()

        notificationCenter.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { _ in
                didBecomeActive()
            }
            .store(in: &cancellables)

        notificationCenter.publisher(for: NSApplication.willTerminateNotification)
            .sink { _ in
                willTerminate()
            }
            .store(in: &cancellables)
    }
}
