import Foundation

private struct VerboseTranscriptionResponse: Decodable {
    let text: String
    let segments: [TranscriptionSegment]?
}

struct VerboseTranscriptionResponseParser {
    let qualityInspector: TranscriptQualityInspector

    func parse(_ data: Data) throws -> TranscriptionResult {
        let result = try JSONDecoder().decode(VerboseTranscriptionResponse.self, from: data)
        let transcript = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !transcript.isEmpty else {
            throw AppError.emptyTranscript
        }

        return TranscriptionResult(
            text: transcript,
            segments: result.segments ?? [],
            qualityFindings: qualityInspector.findings(for: transcript)
        )
    }
}
