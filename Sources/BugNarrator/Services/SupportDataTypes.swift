import Foundation

struct DebugInfoCopyResult {
    let snapshot: DebugInfoSnapshot
    let statusMessage: String
}

struct DebugBundleExportCompletion {
    let bundleURL: URL
    let statusMessage: String
}

struct PrivacyDataExportCompletion {
    let bundleURL: URL
    let statusMessage: String
}

enum SupportDataActionFailure {
    case debugBundleExport
    case privacyDataExport
    case localDataDeletion

    var operation: AppErrorOperation {
        switch self {
        case .debugBundleExport:
            return .diagnosticsExport
        case .privacyDataExport:
            return .privacyExport
        case .localDataDeletion:
            return .sessionLibrary
        }
    }

    var fallback: (String) -> AppError {
        switch self {
        case .debugBundleExport:
            return { _ in .diagnosticsFailure("BugNarrator could not create the debug bundle.") }
        case .privacyDataExport:
            return { _ in .exportFailure("BugNarrator could not create the data export.") }
        case .localDataDeletion:
            return { .storageFailure($0) }
        }
    }
}

@MainActor
final class SupportDataActionPresenter {
    private let setStatus: (AppStatus) -> Void
    private let revealInFinder: (URL) -> AppUtilityActionResult
    private let presentUtilityActionResult: (AppUtilityActionResult) -> Void
    private let presentFailure: (Error, SupportDataActionFailure) -> Void

    init(
        setStatus: @escaping (AppStatus) -> Void,
        revealInFinder: @escaping (URL) -> AppUtilityActionResult,
        presentUtilityActionResult: @escaping (AppUtilityActionResult) -> Void,
        presentFailure: @escaping (Error, SupportDataActionFailure) -> Void = { _, _ in }
    ) {
        self.setStatus = setStatus
        self.revealInFinder = revealInFinder
        self.presentUtilityActionResult = presentUtilityActionResult
        self.presentFailure = presentFailure
    }

    convenience init(
        presentationState: AppPresentationState,
        errorPresenter: AppErrorPresenter,
        utilityActions: AppUtilityActionController,
        utilityResultPresenter: AppUtilityActionResultPresenter
    ) {
        self.init(
            setStatus: { status in
                presentationState.setStatus(status, error: nil)
            },
            revealInFinder: { url in
                utilityActions.revealInFinder(url)
            },
            presentUtilityActionResult: { result in
                utilityResultPresenter.present(result)
            },
            presentFailure: { error, failure in
                _ = errorPresenter.presentError(error, operation: failure.operation, fallback: failure.fallback)
            }
        )
    }

    func presentCopyDebugInfo(_ result: DebugInfoCopyResult) {
        presentSuccess(result.statusMessage)
    }

    func presentDebugBundleExport(_ completion: DebugBundleExportCompletion) {
        presentExportedBundle(at: completion.bundleURL, statusMessage: completion.statusMessage)
    }

    func presentPrivacyDataExport(_ completion: PrivacyDataExportCompletion) {
        presentExportedBundle(at: completion.bundleURL, statusMessage: completion.statusMessage)
    }

    func presentDebugBundleExportFailure(_ error: Error) {
        presentFailure(error, .debugBundleExport)
    }

    func presentPrivacyDataExportFailure(_ error: Error) {
        presentFailure(error, .privacyDataExport)
    }

    func presentLocalDataDeletion(_ outcome: LocalDataDeletionOutcome) {
        presentSuccess(outcome.statusMessage)
    }

    func presentLocalDataDeletion(_ result: LocalDataDeletionResult) {
        switch result {
        case .blocked(let message):
            setStatus(.error(message))
        case .deleted(let outcome):
            presentLocalDataDeletion(outcome)
        }
    }

    func presentLocalDataDeletionFailure(_ error: Error) {
        presentFailure(error, .localDataDeletion)
    }

    private func presentExportedBundle(at bundleURL: URL, statusMessage: String) {
        presentUtilityActionResult(revealInFinder(bundleURL))
        presentSuccess(statusMessage)
    }

    private func presentSuccess(_ message: String) {
        setStatus(.success(message))
    }
}

