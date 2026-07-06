import Foundation

struct RenderedIssueScreenshotAsset: Equatable {
    let fileURL: URL

    var fileName: String {
        fileURL.lastPathComponent
    }
}
