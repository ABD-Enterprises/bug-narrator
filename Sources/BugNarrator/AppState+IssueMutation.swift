import Foundation

extension AppState {
    func updateExtractedIssue(_ updatedIssue: ExtractedIssue, in sessionID: UUID) {
        issueMutationFailurePresenter.attempt {
            try issueExtractionController.updateExtractedIssue(updatedIssue, in: sessionID)
        }
    }

    func setIssueSelection(_ isSelected: Bool, issueID: UUID, in sessionID: UUID) {
        issueMutationFailurePresenter.attempt {
            try issueExtractionController.setIssueSelection(isSelected, issueID: issueID, in: sessionID)
        }
    }

    func setAllIssuesSelected(_ isSelected: Bool, in sessionID: UUID) {
        issueMutationFailurePresenter.attempt {
            try issueExtractionController.setAllIssuesSelected(isSelected, in: sessionID)
        }
    }
}
