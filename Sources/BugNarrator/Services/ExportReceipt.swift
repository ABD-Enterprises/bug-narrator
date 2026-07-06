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

protocol ExportReceiptStoring: Sendable {
    func receipt(for fingerprint: String) async throws -> ExportReceipt?
    func allReceipts() async throws -> [ExportReceipt]
    func markPending(
        fingerprint: String,
        sourceIssueID: UUID,
        destination: ExportDestination,
        targetIdentity: String
    ) async throws
    func markSucceeded(
        fingerprint: String,
        sourceIssueID: UUID,
        destination: ExportDestination,
        targetIdentity: String,
        remoteIdentifier: String,
        remoteURL: URL?
    ) async throws
    func clearReceipt(for fingerprint: String) async throws
}
