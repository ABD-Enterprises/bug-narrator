import Foundation

enum PermissionRecoveryRefreshOutcome: Equatable {
    case unchanged
    case recovered(AppStatus)
}

enum PermissionSettingsOpenResult: Equatable {
    case opened(URL)
    case failed(String)
}
