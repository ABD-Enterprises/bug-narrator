import Foundation

struct TranscriptionSegment: Decodable, Sendable {
    let start: Double
    let end: Double
    let text: String
}
