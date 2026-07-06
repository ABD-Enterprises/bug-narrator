import Foundation

struct RunningApplicationSnapshot: Equatable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
}
