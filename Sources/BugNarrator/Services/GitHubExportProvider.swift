import Foundation

actor GitHubExportProvider {
    let session: URLSession
    let receiptStore: any ExportReceiptStoring
    let retryConfiguration: ExportRetryConfiguration
    let logger = DiagnosticsLogger(category: .export)
    let annotationRenderer = IssueScreenshotAnnotationRenderer()

    init(
        session: URLSession? = nil,
        receiptStore: any ExportReceiptStoring = ExportReceiptStore(),
        retryConfiguration: ExportRetryConfiguration = .default
    ) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 90
            self.session = URLSession(configuration: configuration)
        }
        self.receiptStore = receiptStore
        self.retryConfiguration = retryConfiguration
    }

}
