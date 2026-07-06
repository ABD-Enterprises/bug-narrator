import Foundation

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
