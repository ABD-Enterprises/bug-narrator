import Foundation

enum ExportDestination: String, Codable, CaseIterable, Identifiable {
    case github = "GitHub"
    case jira = "Jira"

    var id: String { rawValue }

    var actionTitle: String {
        "Export to \(rawValue)"
    }
}

