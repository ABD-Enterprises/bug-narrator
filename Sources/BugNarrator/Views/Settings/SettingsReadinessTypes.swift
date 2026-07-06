import SwiftUI

enum SettingsReadinessStatus {
    case ready
    case needsSetup
    case pendingSave
    case locked

    var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .needsSetup:
            return "Needs setup"
        case .pendingSave:
            return "Pending save"
        case .locked:
            return "Locked"
        }
    }

    var symbolName: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"
        case .needsSetup:
            return "exclamationmark.circle.fill"
        case .pendingSave:
            return "clock.fill"
        case .locked:
            return "lock.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready:
            return .green
        case .needsSetup:
            return .orange
        case .pendingSave:
            return .blue
        case .locked:
            return .red
        }
    }
}
