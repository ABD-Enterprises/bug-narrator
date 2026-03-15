import SwiftUI

struct MenuBarLabelView: View {
    let status: AppStatus
    let elapsedTime: String

    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "ladybug.fill")
                    .foregroundStyle(tintColor)

                if status.phase == .recording {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                        .offset(x: 2, y: -1)
                } else if status.phase == .transcribing {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.orange)
                        .offset(x: 3, y: -1)
                } else if status.phase == .success {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.green)
                        .offset(x: 3, y: -1)
                } else if status.phase == .error {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.red)
                        .offset(x: 3, y: -1)
                }
            }

            if status.phase == .recording {
                Text(elapsedTime)
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var tintColor: Color {
        switch status.phase {
        case .idle:
            return .primary
        case .recording:
            return .red
        case .transcribing:
            return .orange
        case .success:
            return .green
        case .error:
            return .red
        }
    }

    private var accessibilityLabel: String {
        switch status.phase {
        case .idle:
            return "BugNarrator idle"
        case .recording:
            return "BugNarrator recording, elapsed time \(elapsedTime)"
        case .transcribing:
            return "BugNarrator transcribing"
        case .success:
            return "BugNarrator success"
        case .error:
            return "BugNarrator error"
        }
    }
}
