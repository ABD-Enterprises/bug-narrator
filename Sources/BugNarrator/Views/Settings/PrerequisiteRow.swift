import Foundation

/// One row in a per-integration prerequisite checklist.
struct PrerequisiteRow: Identifiable {
    let title: String
    let detail: String
    let status: SettingsReadinessStatus

    var id: String {
        title
    }
}

