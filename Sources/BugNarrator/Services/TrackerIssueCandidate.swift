import Foundation

struct TrackerIssueCandidate: Equatable {
    let remoteIdentifier: String
    let title: String
    let summary: String
    let remoteURL: URL?
}
