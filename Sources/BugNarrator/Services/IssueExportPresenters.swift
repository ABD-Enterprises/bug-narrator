import Foundation

enum IssueExportStatusPresenter {
    static func reviewPreparationStatus(destination: ExportDestination) -> AppStatus {
        .transcribing("Checking \(destination.rawValue) for similar open issues...")
    }

    static func reviewReadyStatus(destination: ExportDestination) -> AppStatus {
        .success("Review the similar \(destination.rawValue) issues before export.")
    }

    static func remoteExportStatus(destination: ExportDestination) -> AppStatus {
        .transcribing("Exporting reviewed issues to \(destination.rawValue)...")
    }

    static func completionStatus(_ completion: IssueExportCompletion) -> AppStatus {
        .success(completion.summary)
    }
}
