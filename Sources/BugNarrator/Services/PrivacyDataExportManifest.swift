import Foundation

struct PrivacyDataExportManifest: Encodable {
    let generatedAt: Date
    let sessionCount: Int
    let includesSecrets: Bool
    let exportedFiles: [String]
    let notes: [String]
}
