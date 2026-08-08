import SwiftUI

/// The one-time offer to turn on issue extraction (#912).
///
/// `autoExtractIssues` ships off, because enabling it silently spends the
/// user's provider credit on every session. This surfaces the feature once, in
/// the session library, after a transcript already exists — so the user sees
/// what it would apply to and nothing is charged unless they accept.
///
/// Deliberately not routed through `PostTranscriptionStatusPresenter`. That
/// channel carries *progress*, and emitting a terminal status mid-pipeline
/// overwrote the in-flight "Saving…" message — caught by
/// `PostTranscriptionPipelineControllerTests` on the first attempt.
struct IssueExtractionOfferBanner: View {
    let enable: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Extract issues from your sessions?")
                        .font(.footnote.weight(.semibold))

                    Text("BugNarrator can turn a transcript into draft bugs, UX issues, and follow-up questions. It sends the transcript to your AI provider, which may incur charges on your account.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "sparkles.rectangle.stack")
            }
            .font(.footnote)

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                Button("Turn On") { enable() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button("Not Now") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .fixedSize()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Issue extraction offer")
        .accessibilityIdentifier("issue-extraction-offer-banner")
    }
}
