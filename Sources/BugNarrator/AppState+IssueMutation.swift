import Foundation

extension AppState {
    func updateExtractedIssue(_ updatedIssue: ExtractedIssue, in sessionID: UUID) {
        do {
            try issueExtractionController.updateExtractedIssue(updatedIssue, in: sessionID)
        } catch {
            issueMutationFailurePresenter.presentFailure(error)
        }
    }

    func setIssueSelection(_ isSelected: Bool, issueID: UUID, in sessionID: UUID) {
        do {
            try issueExtractionController.setIssueSelection(isSelected, issueID: issueID, in: sessionID)
        } catch {
            issueMutationFailurePresenter.presentFailure(error)
        }
    }

    func setAllIssuesSelected(_ isSelected: Bool, in sessionID: UUID) {
        do {
            try issueExtractionController.setAllIssuesSelected(isSelected, in: sessionID)
        } catch {
            issueMutationFailurePresenter.presentFailure(error)
        }
    }
}
