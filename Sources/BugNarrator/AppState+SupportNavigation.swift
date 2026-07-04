import Foundation

extension AppState {
    func openAbout() {
        appUtilityActions.openAbout()
    }

    func openChangelog() {
        appUtilityActions.openChangelog()
    }

    func openGitHubRepository() {
        appUtilityActionPresenter.present(appUtilityActions.openGitHubRepository())
    }

    func openDocumentation() {
        appUtilityActionPresenter.present(appUtilityActions.openDocumentation())
    }

    func openIssueReporter() {
        appUtilityActionPresenter.present(appUtilityActions.openIssueReporter())
    }

    func openSupportDevelopment() {
        appUtilityActions.openSupportDevelopment()
    }

    func openSupportDonationPage() {
        appUtilityActionPresenter.present(appUtilityActions.openSupportDonationPage())
    }
}
