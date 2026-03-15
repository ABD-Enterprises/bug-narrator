import SwiftUI

struct SupportView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection
            actionSection
            footerCard
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Support BugNarrator Development")
                .font(.largeTitle.weight(.bold))

            Text("BugNarrator is free to use. If it helps your development workflow, you can optionally support continued development through PayPal.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Support on PayPal")
                .font(.headline)

            Text("The donation flow stays entirely outside the app in your default browser.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                appState.openSupportDonationPage()
            } label: {
                HStack {
                    Label("Open PayPal Donation Page", systemImage: "heart.fill")
                        .font(.body.weight(.semibold))

                    Spacer()

                    Image(systemName: "arrow.up.forward")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel("Open the PayPal donation page")
            .accessibilityHint("Opens PayPal in your default browser")
        }
        .padding(18)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var footerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Thanks for supporting open-source developer tools.")
                .font(.headline)

            Text("BugNarrator never processes payments inside the app and does not store any financial data. The button above opens the PayPal donation page in your default browser.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
