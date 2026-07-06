import Foundation

struct PendingTranscription: Codable, Equatable {
    let audioFileName: String
    var failureReason: PendingTranscriptionFailureReason
    var preservedAt: Date
    var recoveredSourceFileName: String?
    var attemptCount: Int

    init(
        audioFileName: String,
        failureReason: PendingTranscriptionFailureReason,
        preservedAt: Date,
        recoveredSourceFileName: String? = nil,
        attemptCount: Int = 0
    ) {
        self.audioFileName = audioFileName
        self.failureReason = failureReason
        self.preservedAt = preservedAt
        self.recoveredSourceFileName = recoveredSourceFileName
        self.attemptCount = attemptCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        audioFileName = try container.decode(String.self, forKey: .audioFileName)
        failureReason = try container.decode(PendingTranscriptionFailureReason.self, forKey: .failureReason)
        preservedAt = try container.decode(Date.self, forKey: .preservedAt)
        recoveredSourceFileName = try container.decodeIfPresent(String.self, forKey: .recoveredSourceFileName)
        attemptCount = try container.decodeIfPresent(Int.self, forKey: .attemptCount) ?? 0
    }
}
