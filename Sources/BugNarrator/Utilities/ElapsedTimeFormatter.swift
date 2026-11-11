import Foundation

enum ElapsedTimeFormatter {
    static func string(from duration: TimeInterval) -> String {
        // Finite JSON numbers can still exceed Int's range. Check the rounded
        // value before converting; persisted and provider-supplied times are data.
        let rounded = duration.rounded()
        guard rounded.isFinite, rounded > 0, rounded < Double(Int.max) else { return "00:00" }
        let totalSeconds = Int(rounded)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):" + String(format: "%02d:%02d", minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }
}
