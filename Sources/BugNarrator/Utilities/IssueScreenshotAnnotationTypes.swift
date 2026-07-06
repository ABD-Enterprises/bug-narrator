import Foundation

struct RenderedIssueScreenshotAsset: Equatable {
    let fileURL: URL

    var fileName: String {
        fileURL.lastPathComponent
    }
}

/// One annotated screenshot resolved for export: the rendered asset's file
/// name (nil when no annotated asset could be written), plus the source
/// screenshot's file name, time label, and the joined annotation summaries.
/// Tracker providers format these fields into their own line syntax.
struct AnnotatedScreenshotExport: Equatable {
    let renderedFileName: String?
    let screenshotFileName: String
    let timeLabel: String
    let summaries: String
}
