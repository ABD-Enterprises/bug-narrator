import AppKit
import Foundation

struct RunningApplicationSnapshot: Equatable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
}

enum SingleInstanceLaunchDisposition: Equatable {
    case primary
    case secondary(existingProcessIdentifier: pid_t)
}

enum SingleInstanceController {
    static let activationNotificationName = Notification.Name("com.abdenterprises.bugnarrator.activate-existing-instance")

    static func launchDisposition(
        bundleIdentifier: String?,
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        runningApplications: [RunningApplicationSnapshot]
    ) -> SingleInstanceLaunchDisposition {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            return .primary
        }

        let existingProcessIdentifier = runningApplications
            .filter { $0.bundleIdentifier == bundleIdentifier && $0.processIdentifier != currentProcessIdentifier }
            .map(\.processIdentifier)
            .sorted()
            .first

        guard let existingProcessIdentifier else {
            return .primary
        }

        return .secondary(existingProcessIdentifier: existingProcessIdentifier)
    }

    @MainActor
    static func enforcePrimaryInstance() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return true
        }

        let runningApplications = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .map {
                RunningApplicationSnapshot(
                    processIdentifier: $0.processIdentifier,
                    bundleIdentifier: $0.bundleIdentifier
                )
            }

        switch launchDisposition(
            bundleIdentifier: bundleIdentifier,
            runningApplications: runningApplications
        ) {
        case .primary:
            return true
        case .secondary(let existingProcessIdentifier):
            reactivatePrimaryInstance(
                bundleIdentifier: bundleIdentifier,
                existingProcessIdentifier: existingProcessIdentifier
            )
            return false
        }
    }

    @MainActor
    private static func reactivatePrimaryInstance(
        bundleIdentifier: String,
        existingProcessIdentifier: pid_t
    ) {
        DistributedNotificationCenter.default().postNotificationName(
            activationNotificationName,
            object: bundleIdentifier,
            userInfo: nil,
            deliverImmediately: true
        )

        if let existingApplication = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { $0.processIdentifier == existingProcessIdentifier }) {
            existingApplication.activate()
        }
    }
}
