import Foundation

enum IssueExportReviewPolicy {
    static func preparedIssues(from review: IssueExportReview) throws -> [ExtractedIssue] {
        try review.items.compactMap { item in
            switch item.resolution {
            case .exportNew:
                return item.issue
            case .linkAsRelated:
                guard let match = item.selectedMatch else {
                    throw AppError.exportFailure("Choose a related \(review.destination.rawValue) issue before linking.")
                }

                var issue = item.issue
                issue.note = trackerContextNote(for: .linkAsRelated, match: match)
                return issue
            case .markDuplicate:
                return nil
            }
        }
    }

    static func duplicateMatchResults(from review: IssueExportReview) throws -> [ExportResult] {
        try review.items.compactMap { item in
            guard item.resolution == .markDuplicate else {
                return nil
            }

            guard let match = item.selectedMatch else {
                throw AppError.exportFailure("Choose an existing \(review.destination.rawValue) issue to mark as duplicate.")
            }

            return ExportResult(
                sourceIssueID: item.issue.id,
                destination: review.destination,
                remoteIdentifier: match.remoteIdentifier,
                remoteURL: match.remoteURL
            )
        }
    }

    static func exportSummary(
        for results: [ExportResult],
        duplicateCount: Int,
        destination: ExportDestination
    ) -> String {
        let createdCount = max(0, results.count - duplicateCount)

        if duplicateCount > 0, createdCount > 0 {
            return "Exported \(createdCount) new issue\(createdCount == 1 ? "" : "s") to \(destination.rawValue) and linked \(duplicateCount) to existing tracker items."
        }

        if duplicateCount > 0 {
            return "Linked \(duplicateCount) issue\(duplicateCount == 1 ? "" : "s") to existing \(destination.rawValue) items without creating duplicates."
        }

        return "Exported \(createdCount) issues to \(destination.rawValue)."
    }

    private static func trackerContextNote(for resolution: SimilarIssueResolution, match: SimilarIssueMatch) -> String {
        switch resolution {
        case .exportNew:
            return ""
        case .linkAsRelated:
            return "Related to \(match.remoteIdentifier) (\(match.confidenceLabel) match): \(match.title). \(match.reasoning)"
        case .markDuplicate:
            return "Marked as duplicate of \(match.remoteIdentifier) (\(match.confidenceLabel) match): \(match.title). \(match.reasoning)"
        }
    }
}
