import Foundation

struct ExportReceipt: Codable, Equatable {
    enum State: String, Codable {
        case pending
        case succeeded
    }

    let fingerprint: String
    let sourceIssueID: UUID
    let destination: ExportDestination
    let targetIdentity: String
    let state: State
    let remoteIdentifier: String?
    let remoteURL: URL?
    let updatedAt: Date

    func asExportResult() -> ExportResult? {
        guard state == .succeeded, let remoteIdentifier else {
            return nil
        }

        return ExportResult(
            sourceIssueID: sourceIssueID,
            destination: destination,
            remoteIdentifier: remoteIdentifier,
            remoteURL: remoteURL,
            exportedAt: updatedAt
        )
    }
}
