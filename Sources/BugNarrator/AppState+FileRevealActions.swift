import Foundation

extension AppState {
    func openScreenshot(_ screenshot: SessionScreenshot) {
        appUtilityActionPresenter.present(appUtilityActions.openScreenshot(screenshot))
    }

    func showRevealInFinderToast(_ message: String, revealing url: URL) {
        transientToastController.showToast(
            message,
            style: .success,
            durationNanoseconds: 5_000_000_000,
            action: TransientToastAction(
                title: "Reveal",
                accessibilityLabel: "Reveal in Finder"
            ) { [weak self] in
                self?.revealInFinder(url)
            }
        )
    }

    func revealInFinder(_ url: URL) {
        appUtilityActionPresenter.present(appUtilityActions.revealInFinder(url))
    }
}
