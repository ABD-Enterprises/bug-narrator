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
    func receipt(for fingerprint: String) async -> ExportReceipt?
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

actor ExportReceiptStore: ExportReceiptStoring {
    private let fileManager: FileManager
    private let storageURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cache: [String: ExportReceipt]?

    init(
        fileManager: FileManager = .default,
        storageURL: URL = AppSupportLocation.appDirectory()
            .appendingPathComponent("export-receipts.json", isDirectory: false)
    ) {
        self.fileManager = fileManager
        self.storageURL = storageURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func receipt(for fingerprint: String) async -> ExportReceipt? {
        await loadCacheIfNeeded()[fingerprint]
    }

    func markPending(
        fingerprint: String,
        sourceIssueID: UUID,
        destination: ExportDestination,
        targetIdentity: String
    ) async throws {
        var receipts = await loadCacheIfNeeded()
        receipts[fingerprint] = ExportReceipt(
            fingerprint: fingerprint,
            sourceIssueID: sourceIssueID,
            destination: destination,
            targetIdentity: targetIdentity,
            state: .pending,
            remoteIdentifier: nil,
            remoteURL: nil,
            updatedAt: Date()
        )
        try await persist(receipts)
    }

    func markSucceeded(
        fingerprint: String,
        sourceIssueID: UUID,
        destination: ExportDestination,
        targetIdentity: String,
        remoteIdentifier: String,
        remoteURL: URL?
    ) async throws {
        var receipts = await loadCacheIfNeeded()
        receipts[fingerprint] = ExportReceipt(
            fingerprint: fingerprint,
            sourceIssueID: sourceIssueID,
            destination: destination,
            targetIdentity: targetIdentity,
            state: .succeeded,
            remoteIdentifier: remoteIdentifier,
            remoteURL: remoteURL,
            updatedAt: Date()
        )
        try await persist(receipts)
    }

    func clearReceipt(for fingerprint: String) async throws {
        var receipts = await loadCacheIfNeeded()
        receipts.removeValue(forKey: fingerprint)
        try await persist(receipts)
    }

    private func loadCacheIfNeeded() async -> [String: ExportReceipt] {
        if let cache {
            return cache
        }

        guard fileManager.fileExists(atPath: storageURL.path) else {
            cache = [:]
            return [:]
        }

        do {
            let data = try Data(contentsOf: storageURL)
            let receipts = try decoder.decode([String: ExportReceipt].self, from: data)
            cache = receipts
            return receipts
        } catch {
            cache = [:]
            return [:]
        }
    }

    private func persist(_ receipts: [String: ExportReceipt]) async throws {
        cache = receipts

        let directoryURL = storageURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        let data = try encoder.encode(receipts)
        try data.write(to: storageURL, options: .atomic)
    }
}

enum TrackerExportFingerprint {
    static func make(
        destination: ExportDestination,
        targetIdentity: String,
        sessionID: UUID,
        issueID: UUID
    ) -> String {
        let normalizedValue = [
            destination.rawValue.lowercased(),
            targetIdentity.lowercased(),
            sessionID.uuidString.lowercased(),
            issueID.uuidString.lowercased()
        ]
        .joined(separator: "|")

        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211

        for byte in normalizedValue.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }

        return String(format: "bnexp-%016llx", hash)
    }

    static func marker(for fingerprint: String) -> String {
        "bugnarrator-export-id: \(fingerprint)"
    }
}
