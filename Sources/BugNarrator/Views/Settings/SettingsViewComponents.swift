import SwiftUI

/// Shared field-layout components used across the Settings panes. Extracted from
/// `SettingsView` (#355) so per-pane views can render byte-identical field rows
/// as the panes are split out of the monolithic settings body.

/// A label/value row: a fixed-width title on the left and arbitrary content on
/// the right.
@ViewBuilder
func settingsLabeledField<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
) -> some View {
    HStack(alignment: .top) {
        Text(title)
            .frame(width: 170, alignment: .leading)
        content()
    }
}

/// A secondary-styled introductory line for a settings section.
func settingsSectionIntro(_ text: String) -> some View {
    Text(text)
        .font(.footnote)
        .foregroundStyle(.secondary)
}

/// Help text shown on credential fields while secure controls are disabled
/// (a recording/transcription is in progress).
let settingsSecureControlsDisabledHint = "Disabled while recording or transcribing is in progress."
