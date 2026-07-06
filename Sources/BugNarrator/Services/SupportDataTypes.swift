import Foundation

struct DebugInfoCopyResult {
    let snapshot: DebugInfoSnapshot
    let statusMessage: String
}

struct DebugBundleExportCompletion {
    let bundleURL: URL
    let statusMessage: String
}

struct PrivacyDataExportCompletion {
    let bundleURL: URL
    let statusMessage: String
}

enum SupportDataActionFailure {
    case debugBundleExport
    case privacyDataExport
    case localDataDeletion

    var operation: AppErrorOperation {
        switch self {
        case .debugBundleExport:
            return .diagnosticsExport
        case .privacyDataExport:
            return .privacyExport
        case .localDataDeletion:
            return .sessionLibrary
        }
    }

    var fallback: (String) -> AppError {
        switch self {
        case .debugBundleExport:
            return { _ in .diagnosticsFailure("BugNarrator could not create the debug bundle.") }
        case .privacyDataExport:
            return { _ in .exportFailure("BugNarrator could not create the data export.") }
        case .localDataDeletion:
            return { .storageFailure($0) }
        }
    }
}

