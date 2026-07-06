import Foundation

actor ExportReceiptStore: ExportReceiptStoring {
    static let defaultStorageURL = AppSupportLocation.appDirectory()
        .appendingPathComponent("export-receipts.json", isDirectory: false)

    private let fileManager: FileManager
    private let storageURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = DiagnosticsLogger(category: .export)
    private var cache: [String: ExportReceipt]?

    init(
        fileManager: FileManager = .default,
        storageURL: URL = ExportReceiptStore.defaultStorageURL
    ) {
        self.fileManager = fileManager
        self.storageURL = storageURL
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func receipt(for fingerprint: String) async throws -> ExportReceipt? {
        try await loadCacheIfNeeded()[fingerprint]
    }

    func allReceipts() async throws -> [ExportReceipt] {
        try await loadCacheIfNeeded()
            .values
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func markPending(
        fingerprint: String,
        sourceIssueID: UUID,
        destination: ExportDestination,
        targetIdentity: String
    ) async throws {
        var receipts = try await loadCacheIfNeeded()
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
        var receipts = try await loadCacheIfNeeded()
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
        var receipts = try await loadCacheIfNeeded()
        receipts.removeValue(forKey: fingerprint)
        try await persist(receipts)
    }

    private func loadCacheIfNeeded() async throws -> [String: ExportReceipt] {
        if let cache {
            return cache
        }

        guard fileManager.fileExists(atPath: storageURL.path) else {
            cache = [:]
            return [:]
        }

        // Fail closed on any read/decode failure. Treating a corrupt or unreadable
        // receipt store as "no receipts" would forget prior successful exports and
        // silently re-create duplicate issues, so we stop export instead and leave
        // a clear, actionable error. We do NOT cache an empty dict here, so the
        // store keeps failing closed until the file is repaired or cleared.
        let data: Data
        do {
            data = try Data(contentsOf: storageURL)
        } catch {
            logger.error(
                "export_receipt_store_unreadable",
                "Could not read the export receipt store; exports are paused to avoid duplicate issues.",
                metadata: ["error": String(describing: type(of: error))]
            )
            throw AppError.exportFailure(
                "BugNarrator could not read its export history, so exports are paused to avoid creating duplicate issues. Try again, or clear local data in Settings if this persists."
            )
        }

        do {
            let receipts = try decoder.decode([String: ExportReceipt].self, from: data)
            cache = receipts
            return receipts
        } catch {
            backUpCorruptReceiptStore()
            logger.error(
                "export_receipt_store_corrupt",
                "The export receipt store is corrupt; exports are paused to avoid duplicate issues.",
                metadata: ["error": String(describing: type(of: error))]
            )
            throw AppError.exportFailure(
                "BugNarrator's export history file is corrupt, so exports are paused to avoid creating duplicate issues. Clear local data in Settings to reset it."
            )
        }
    }

    /// Preserves the first corrupt snapshot for forensics without overwriting a
    /// previously-captured one (copy only if absent).
    private func backUpCorruptReceiptStore() {
        let backupURL = storageURL.deletingLastPathComponent()
            .appendingPathComponent("export-receipts.corrupt.json")
        guard !fileManager.fileExists(atPath: backupURL.path) else {
            return
        }
        do {
            try fileManager.copyItem(at: storageURL, to: backupURL)
        } catch {
            logger.warning(
                "export_receipt_backup_failed",
                "Could not back up the corrupt export receipt store.",
                metadata: ["error": String(describing: type(of: error))]
            )
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
