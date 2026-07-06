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

@MainActor
final class AppPresentationState: ObservableObject {
    @Published private(set) var status: AppStatus
    @Published private(set) var currentError: AppError?
    @Published private(set) var transientToast: TransientToast?

    init(
        status: AppStatus = .idle(),
        currentError: AppError? = nil,
        transientToast: TransientToast? = nil
    ) {
        self.status = status
        self.currentError = currentError
        self.transientToast = transientToast
    }

    func setStatus(_ status: AppStatus, error: AppError? = nil) {
        self.status = status
        currentError = error
    }

    func showToast(_ toast: TransientToast) {
        transientToast = toast
    }

    func dismissToast() {
        transientToast = nil
    }
}
