import Foundation

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
