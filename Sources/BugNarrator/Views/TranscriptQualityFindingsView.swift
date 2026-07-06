import SwiftUI

struct TranscriptQualityFindingsView: View {
    let findings: [TranscriptQualityFinding]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(findings) { finding in
                Label(finding.message, systemImage: icon(for: finding))
                    .font(.subheadline)
                    .foregroundStyle(finding.severity == .error ? .red : .orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func icon(for finding: TranscriptQualityFinding) -> String {
        switch finding.kind {
        case .repeatedText:
            return "repeat"
        case .boilerplateText:
            return "text.quote"
        case .unexpectedLanguageScript:
            return "globe.asia.australia"
        case .abruptEnding:
            return "text.badge.exclamationmark"
        case .shortTranscript:
            return "text.magnifyingglass"
        }
    }
}
