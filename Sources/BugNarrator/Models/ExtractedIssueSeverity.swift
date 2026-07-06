import Foundation

enum ExtractedIssueSeverity: String, Codable, CaseIterable, Identifiable {
    case critical = "Critical"
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var id: String { rawValue }
}
