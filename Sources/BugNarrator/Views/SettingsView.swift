import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settingsStore: SettingsStore
    @State private var showDeleteAllLocalDataConfirmation = false
    @State private var selectedSection: SettingsSection = .general

    /// The tabbed sections of Settings. A segmented `Picker` drives selection —
    /// macOS `TabView` does not expose addressable tab controls in this window,
    /// so a segmented control is the native, UI-testable equivalent (#355).
    enum SettingsSection: String, CaseIterable, Identifiable {
        case general = "General"
        case aiEngines = "AI Engines"
        case audio = "Audio"
        case integrations = "Integrations"
        case diagnostics = "Diagnostics & Privacy"

        var id: String { rawValue }
        var title: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("BugNarrator Settings")
                    .font(.title2.weight(.semibold))

                Text("Set up your AI provider, review workflow defaults, export destinations, and local diagnostics in one place.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            statusSummary

            Picker("Settings section", selection: $selectedSection) {
                ForEach(SettingsSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("settings.tabs")
            .accessibilityLabel("Settings section")

            switch selectedSection {
            case .general:
                generalTab
            case .aiEngines:
                aiEnginesTab
            case .audio:
                audioTab
            case .integrations:
                integrationsTab
            case .diagnostics:
                diagnosticsTab
            }

            if secureControlsDisabled {
                Text("Credential changes are disabled while recording, transcription, extraction, or export is in progress.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(minWidth: 660, minHeight: 580)
        .alert("Delete all local BugNarrator data?", isPresented: $showDeleteAllLocalDataConfirmation) {
            Button("Delete All Data", role: .destructive) {
                Task {
                    await appState.deleteAllLocalData()
                }
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes local sessions, local diagnostics, and local export history from this Mac. Keychain credentials remain stored until you remove them separately.")
        }
    }

    // MARK: - Tabs (pure UI grouping of the extracted panes; #355)

    private var generalTab: some View {
        settingsTabScroll {
            SettingsWorkflowDefaultsPane(settingsStore: settingsStore)

            SettingsGlobalHotkeysPane(
                settingsStore: settingsStore,
                secureControlsDisabled: secureControlsDisabled
            )
        }
    }

    private var aiEnginesTab: some View {
        settingsTabScroll {
            GroupBox("Before You Start") {
                VStack(alignment: .leading, spacing: 10) {
                    if settingsStore.aiProvider == .parakeetLocal {
                        Text("Local transcription is selected.")
                            .font(.headline)

                        Text("BugNarrator will transcribe recordings on this Mac using Parakeet. No API key, no cloud upload, no cost. Start the local transcription server before recording.")
                            .foregroundStyle(.secondary)

                        Text("Run in Terminal: local-transcription/venv/bin/python local-transcription/server.py --preload")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Text("BugNarrator requires your own AI provider configuration.")
                            .font(.headline)

                        Text("BugNarrator does not ship with bundled AI access or credits. Configure your provider below before you transcribe a session or run issue extraction.")
                            .foregroundStyle(.secondary)

                        Text("Transcription and issue extraction use the selected provider and may incur charges on that provider account.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            AISetupSectionsView(
                appState: appState,
                settingsStore: settingsStore,
                secureControlsDisabled: secureControlsDisabled
            )
        }
    }

    private var audioTab: some View {
        settingsTabScroll {
            SettingsRecordingAudioPane(
                settingsStore: settingsStore,
                secureControlsDisabled: secureControlsDisabled
            )

            SettingsPermissionsPane(
                appState: appState,
                settingsStore: settingsStore
            )
        }
    }

    private var integrationsTab: some View {
        settingsTabScroll {
            SettingsGitHubExportPane(
                appState: appState,
                settingsStore: settingsStore,
                secureControlsDisabled: secureControlsDisabled
            )

            SettingsJiraExportPane(
                appState: appState,
                settingsStore: settingsStore,
                secureControlsDisabled: secureControlsDisabled
            )
        }
    }

    private var diagnosticsTab: some View {
        settingsTabScroll {
            SettingsDiagnosticsPrivacyPane(
                appState: appState,
                settingsStore: settingsStore,
                secureControlsDisabled: secureControlsDisabled,
                showDeleteAllLocalDataConfirmation: $showDeleteAllLocalDataConfirmation
            )
        }
    }

    @ViewBuilder
    private func settingsTabScroll<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Preserve the identifier the UI-test scroll helpers look for; only the
        // selected tab's scroll view is in the tree at a time.
        .accessibilityLabel("Settings scroll area")
    }

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Setup Status")
                .font(.headline)

            let configured = setupConfiguredCount
            let total = setupTotalCount
            VStack(alignment: .leading, spacing: 4) {
                Text("\(configured) of \(total) configured")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(configured), total: Double(total))
                    .accessibilityLabel("Setup progress: \(configured) of \(total) configured")
            }

            VStack(spacing: 8) {
                settingsStatusRow(
                    title: settingsStore.aiProvider.statusTitle,
                    detail: "Transcription and issue extraction",
                    status: openAIReadiness,
                    accessibilityLabel: "AI provider status: \(openAIReadiness.title)"
                )

                settingsStatusRow(
                    title: "GitHub Export",
                    detail: "Issues destination",
                    status: gitHubReadiness,
                    accessibilityLabel: "GitHub export status: \(gitHubReadiness.title)"
                )

                settingsStatusRow(
                    title: "Jira Export",
                    detail: "Cloud project destination",
                    status: jiraReadiness,
                    accessibilityLabel: "Jira export status: \(jiraReadiness.title)"
                )
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private var secureControlsDisabled: Bool {
        appState.status.phase == .recording || appState.status.phase == .transcribing
    }

    private var setupTotalCount: Int { 3 }

    private var setupConfiguredCount: Int {
        var count = 0
        if openAIReadiness == .ready { count += 1 }
        if gitHubReadiness == .ready { count += 1 }
        if jiraReadiness == .ready { count += 1 }
        return count
    }

    private var openAIReadiness: SettingsReadinessStatus {
        SettingsReadiness.openAIReadiness(settingsStore)
    }

    private var gitHubReadiness: SettingsReadinessStatus {
        SettingsReadiness.gitHubReadiness(settingsStore)
    }

    private var jiraReadiness: SettingsReadinessStatus {
        SettingsReadiness.jiraReadiness(settingsStore)
    }

    @ViewBuilder
    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        settingsLabeledField(title: title, content: content)
    }

    private func sectionIntro(_ text: String) -> some View {
        settingsSectionIntro(text)
    }

    private func settingsStatusRow(
        title: String,
        detail: String,
        status: SettingsReadinessStatus,
        accessibilityLabel: String
    ) -> some View {
        BugNarrator.settingsStatusRow(
            title: title,
            detail: detail,
            status: status,
            accessibilityLabel: accessibilityLabel
        )
    }
}

struct CredentialTokenField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let isDisabled: Bool
    let accessibilityLabel: String
    var revealWhenNotEditing: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> CredentialTokenTextField {
        let textField = CredentialTokenTextField()
        textField.configureCredentialInput()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.setAccessibilityLabel(accessibilityLabel)
        return textField
    }

    func updateNSView(_ textField: CredentialTokenTextField, context: Context) {
        context.coordinator.parent = self
        textField.configureCredentialInput()
        textField.placeholderString = placeholder
        textField.setAccessibilityLabel(accessibilityLabel)
        textField.isEnabled = !isDisabled

        let displayValue = (context.coordinator.isEditing || revealWhenNotEditing)
            ? text
            : Self.maskedDisplayValue(for: text)
        if textField.stringValue != displayValue {
            textField.stringValue = displayValue
        }
    }

    static func maskedDisplayValue(for value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return ""
        }

        let suffix = trimmedValue.suffix(min(4, trimmedValue.count))
        return "••••••••\(suffix)"
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CredentialTokenField
        var isEditing = false

        init(_ parent: CredentialTokenField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isEditing = true
            guard let textField = notification.object as? NSTextField else {
                return
            }

            if let editor = textField.currentEditor() {
                editor.string = parent.text
                editor.selectedRange = NSRange(location: parent.text.count, length: 0)
            } else {
                textField.stringValue = parent.text
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isEditing = false
            guard let textField = notification.object as? NSTextField else {
                return
            }

            parent.text = textField.stringValue
            textField.stringValue = CredentialTokenField.maskedDisplayValue(for: parent.text)
        }
    }
}

final class CredentialTokenTextField: NSTextField {
    func configureCredentialInput() {
        isBezeled = true
        bezelStyle = .roundedBezel
        drawsBackground = true
        isEditable = true
        isSelectable = true
        usesSingleLineMode = true
        lineBreakMode = .byTruncatingMiddle
        isAutomaticTextCompletionEnabled = false

        if #available(macOS 11.0, *) {
            contentType = nil
        }

        cell?.isScrollable = true
        cell?.lineBreakMode = .byTruncatingMiddle
    }

    override func becomeFirstResponder() -> Bool {
        configureCredentialInput()
        let didBecomeFirstResponder = super.becomeFirstResponder()
        disableEditorAssistance()
        return didBecomeFirstResponder
    }

    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        disableEditorAssistance()
    }

    private func disableEditorAssistance() {
        guard let textView = currentEditor() as? NSTextView else {
            return
        }

        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
    }
}
