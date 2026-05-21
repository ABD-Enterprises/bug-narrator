import Combine
import Foundation

@MainActor
final class ExportHistoryController: ObservableObject {
    @Published private(set) var exportHistory: [ExportReceipt]

    private let exportService: any IssueExporting
    private let exportLogger = DiagnosticsLogger(category: .export)

    init(
        exportService: any IssueExporting,
        exportHistory: [ExportReceipt] = []
    ) {
        self.exportService = exportService
        self.exportHistory = exportHistory
    }

    func refreshExportHistory() async {
        do {
            exportHistory = try await exportService.exportHistory()
        } catch {
            let appError = (error as? AppError) ?? .exportFailure(error.localizedDescription)
            exportLogger.warning(
                "export_history_refresh_failed",
                appError.userMessage,
                metadata: [
                    "context": "export_history_refresh_failed",
                    "operation": "export_history"
                ]
            )
            exportHistory = []
        }
    }
}
