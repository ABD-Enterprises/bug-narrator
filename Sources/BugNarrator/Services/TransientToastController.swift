import Foundation

@MainActor
final class TransientToastController {
    private let presentationState: AppPresentationState
    private var dismissTask: Task<Void, Never>?

    init(presentationState: AppPresentationState) {
        self.presentationState = presentationState
    }

    deinit {
        dismissTask?.cancel()
    }

    func showToast(
        _ message: String,
        style: TransientToastStyle = .success,
        durationNanoseconds: UInt64 = 2_000_000_000
    ) {
        dismissTask?.cancel()
        presentationState.showToast(TransientToast(message: message, style: style))
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: durationNanoseconds)
            guard !Task.isCancelled else {
                return
            }

            self?.presentationState.dismissToast()
        }
    }

    func dismissToast() {
        dismissTask?.cancel()
        presentationState.dismissToast()
    }
}
