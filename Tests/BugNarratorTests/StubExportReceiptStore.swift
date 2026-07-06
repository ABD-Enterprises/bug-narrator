import Foundation
@testable import BugNarrator

/// In-memory `ExportReceiptStoring` for tests that need to drive the receipt
/// lifecycle — e.g. seeding a `.pending` receipt to exercise the reconcile
/// path — without the file-backed production store. Records `markSucceeded`
/// calls so a test can assert reconciliation occurred.
actor StubExportReceiptStore: ExportReceiptStoring {
    private(set) var receipts: [String: ExportReceipt] = [:]
    private(set) var markSucceededCalls: [(fingerprint: String, remoteIdentifier: String)] = []

    func seedPending(
        fingerprint: String,
        sourceIssueID: UUID,
        destination: ExportDestination,
        targetIdentity: String
    ) {
        receipts[fingerprint] = ExportReceipt(
            fingerprint: fingerprint,
            sourceIssueID: sourceIssueID,
            destination: destination,
            targetIdentity: targetIdentity,
            state: .pending,
            remoteIdentifier: nil,
            remoteURL: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func receipt(for fingerprint: String) async throws -> ExportReceipt? {
        receipts[fingerprint]
    }

    func allReceipts() async throws -> [ExportReceipt] {
        Array(receipts.values)
    }

    func markPending(
        fingerprint: String,
        sourceIssueID: UUID,
        destination: ExportDestination,
        targetIdentity: String
    ) async throws {
        receipts[fingerprint] = ExportReceipt(
            fingerprint: fingerprint,
            sourceIssueID: sourceIssueID,
            destination: destination,
            targetIdentity: targetIdentity,
            state: .pending,
            remoteIdentifier: nil,
            remoteURL: nil,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func markSucceeded(
        fingerprint: String,
        sourceIssueID: UUID,
        destination: ExportDestination,
        targetIdentity: String,
        remoteIdentifier: String,
        remoteURL: URL?
    ) async throws {
        markSucceededCalls.append((fingerprint, remoteIdentifier))
        receipts[fingerprint] = ExportReceipt(
            fingerprint: fingerprint,
            sourceIssueID: sourceIssueID,
            destination: destination,
            targetIdentity: targetIdentity,
            state: .succeeded,
            remoteIdentifier: remoteIdentifier,
            remoteURL: remoteURL,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func clearReceipt(for fingerprint: String) async throws {
        receipts.removeValue(forKey: fingerprint)
    }
}
