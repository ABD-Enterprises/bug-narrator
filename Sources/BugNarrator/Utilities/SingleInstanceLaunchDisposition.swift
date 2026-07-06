import Foundation

enum SingleInstanceLaunchDisposition: Equatable {
    case primary
    case secondary(existingProcessIdentifier: pid_t)
}
