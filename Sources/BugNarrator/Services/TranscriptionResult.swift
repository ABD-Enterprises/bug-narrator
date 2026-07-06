import Foundation

struct TranscriptionResult: Sendable {
    let text: String
    let segments: [TranscriptionSegment]
    let qualityFindings: [TranscriptQualityFinding]

    init(
        text: String,
        segments: [TranscriptionSegment],
        qualityFindings: [TranscriptQualityFinding] = []
    ) {
        self.text = text
        self.segments = segments
        self.qualityFindings = qualityFindings
    }
}

