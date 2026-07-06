import Foundation
@testable import BugNarrator

@MainActor
final class MockDebugBundleExporter: DebugBundleExporting {
    var exportResult: Result<URL?, Error> = .success(nil)
    private(set) var exportedSnapshots: [DebugBundleSnapshot] = []

    func export(snapshot: DebugBundleSnapshot) throws -> URL? {
        exportedSnapshots.append(snapshot)
        return try exportResult.get()
    }
}
