import Foundation

enum ExtractedIssueCategory: String, Codable, CaseIterable, Identifiable {
    case bug = "Bug"
    case uxIssue = "UX Issue"
    case enhancement = "Enhancement"
    case followUp = "Question / Follow-up"

    var id: String { rawValue }
}

enum ExtractedIssueSeverity: String, Codable, CaseIterable, Identifiable {
    case critical = "Critical"
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var id: String { rawValue }
}

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
