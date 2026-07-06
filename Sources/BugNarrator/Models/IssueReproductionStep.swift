import Foundation

struct IssueReproductionStep: Identifiable, Codable, Equatable {
    let id: UUID
    var instruction: String
    var expectedResult: String?
    var actualResult: String?
    var timestamp: TimeInterval?
    var screenshotID: UUID?

    init(
        id: UUID = UUID(),
        instruction: String,
        expectedResult: String? = nil,
        actualResult: String? = nil,
        timestamp: TimeInterval? = nil,
        screenshotID: UUID? = nil
    ) {
        self.id = id
        self.instruction = instruction
        self.expectedResult = expectedResult
        self.actualResult = actualResult
        self.timestamp = timestamp
        self.screenshotID = screenshotID
    }

    var timestampLabel: String? {
        guard let timestamp else {
            return nil
        }

        return ElapsedTimeFormatter.string(from: timestamp)
    }
}
