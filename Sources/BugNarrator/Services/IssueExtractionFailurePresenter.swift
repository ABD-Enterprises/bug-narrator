import Foundation

@MainActor
final class IssueExtractionFailurePresenter {
    private let errorPresenter: AppErrorPresenter
    var prepareErrorPresentationSideEffects: () -> Void

    init(
        errorPresenter: AppErrorPresenter,
        prepareErrorPresentationSideEffects: @escaping () -> Void = {}
    ) {
        self.errorPresenter = errorPresenter
        self.prepareErrorPresentationSideEffects = prepareErrorPresentationSideEffects
    }

    func presentFailure(_ error: Error) {
        prepareErrorPresentationSideEffects()
        _ = errorPresenter.presentError(error, operation: .issueExtraction, fallback: { .storageFailure($0) })
    }
}
