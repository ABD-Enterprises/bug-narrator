import Foundation

extension AppState {
    // MARK: - Methods

    func refreshExportHistory() async {
        await exportHistoryController.refreshExportHistory()
    }

    // MARK: - Computed properties

    var exportHistory: [ExportReceipt] {
        exportHistoryController.exportHistory
    }
}
