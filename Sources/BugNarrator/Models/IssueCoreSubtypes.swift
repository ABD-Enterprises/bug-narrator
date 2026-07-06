import Foundation

enum ExtractedIssueCategory: String, Codable, CaseIterable, Identifiable {
    case bug = "Bug"
    case uxIssue = "UX Issue"
    case enhancement = "Enhancement"
    case followUp = "Question / Follow-up"

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

struct IssueScreenshotAnnotation: Identifiable, Codable, Equatable {
    enum Style: String, Codable {
        case highlight
    }

    let id: UUID
    var screenshotID: UUID
    var label: String?
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var confidence: Double?
    var style: Style

    init(
        id: UUID = UUID(),
        screenshotID: UUID,
        label: String? = nil,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        confidence: Double? = nil,
        style: Style = .highlight
    ) {
        self.id = id
        self.screenshotID = screenshotID
        self.label = label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
        self.width = min(max(width, 0.05), 1)
        self.height = min(max(height, 0.05), 1)
        self.confidence = confidence
        self.style = style

        clampRectIntoBounds()
    }

    var normalizedRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var confidenceLabel: String? {
        guard let confidence else {
            return nil
        }

        return "\(Int((confidence * 100).rounded()))%"
    }

    var exportDescription: String {
        let normalized = normalizedRect
        let xPercent = Int((normalized.minX * 100).rounded())
        let yPercent = Int((normalized.minY * 100).rounded())
        let widthPercent = Int((normalized.width * 100).rounded())
        let heightPercent = Int((normalized.height * 100).rounded())

        var parts = [
            label ?? "UI highlight",
            "x \(xPercent)%",
            "y \(yPercent)%",
            "w \(widthPercent)%",
            "h \(heightPercent)%"
        ]

        if let confidenceLabel {
            parts.append("confidence \(confidenceLabel)")
        }

        return parts.joined(separator: " • ")
    }

    mutating func move(x deltaX: Double, y deltaY: Double) {
        x += deltaX
        y += deltaY
        clampRectIntoBounds()
    }

    mutating func updateRect(_ rect: CGRect) {
        x = min(max(rect.origin.x, 0), 1)
        y = min(max(rect.origin.y, 0), 1)
        width = min(max(rect.width, 0.05), 1)
        height = min(max(rect.height, 0.05), 1)
        clampRectIntoBounds()
    }

    private mutating func clampRectIntoBounds() {
        width = min(max(width, 0.05), 1)
        height = min(max(height, 0.05), 1)
        x = min(max(x, 0), max(0, 1 - width))
        y = min(max(y, 0), max(0, 1 - height))
    }
}
