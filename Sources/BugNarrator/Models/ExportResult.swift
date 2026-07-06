import Foundation

struct ExportResult: Identifiable, Equatable {
    let id: UUID
    let sourceIssueID: UUID
    let destination: ExportDestination
    let remoteIdentifier: String
    let remoteURL: URL?
    let exportedAt: Date

    init(
        id: UUID = UUID(),
        sourceIssueID: UUID,
        destination: ExportDestination,
        remoteIdentifier: String,
        remoteURL: URL?,
        exportedAt: Date = Date()
    ) {
        self.id = id
        self.sourceIssueID = sourceIssueID
        self.destination = destination
        self.remoteIdentifier = remoteIdentifier
        self.remoteURL = remoteURL
        self.exportedAt = exportedAt
    }
}

