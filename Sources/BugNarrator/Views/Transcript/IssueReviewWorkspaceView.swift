import SwiftUI

struct IssueReviewWorkspaceView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var transcriptStore: TranscriptStore

    let session: TranscriptSession
    let availableWidth: CGFloat

    var body: some View {
        extractedIssuesSection(session, availableWidth: availableWidth)
    }

    private func extractedIssuesSection(_ session: TranscriptSession, availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let extraction = session.issueExtraction {
                VStack(alignment: .leading, spacing: 14) {
                    Text(extraction.guidanceNote.isEmpty ? "Review before exporting." : extraction.guidanceNote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if extraction.issues.isEmpty {
                        emptyDetailState(
                            title: "No extracted issues",
                            message: "Issue extraction ran, but it did not return any draft issues for this session."
                        )
                    } else {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(extraction.issues) { issue in
                                issueReviewRow(issue: issue, session: session, availableWidth: availableWidth)
                            }
                        }

                        Divider()
                            .padding(.top, 4)

                        Text(ReviewWorkspace.selectedIssueSummary(for: session))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                issueExportButton(destination: .github, session: session)
                                issueExportButton(destination: .jira, session: session)
                            }

                            if let gitHubSetupMessage = appState.issueExportSetupMessage(for: .github) {
                                Text(gitHubSetupMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let jiraSetupMessage = appState.issueExportSetupMessage(for: .jira) {
                                Text(jiraSetupMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let gitHubRoutingMessage = appState.issueExportRoutingMessage(for: .github, session: session) {
                                Text(gitHubRoutingMessage)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            if let jiraRoutingMessage = appState.issueExportRoutingMessage(for: .jira, session: session) {
                                Text(jiraRoutingMessage)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Run issue extraction to turn this transcript into reviewable draft bugs, UX issues, enhancements, and follow-ups.")
                        .foregroundStyle(.secondary)

                    Button(appState.isExtractingIssues(for: session) ? "Extracting Issues..." : "Extract Issues") {
                        appState.selectedTranscriptID = session.id
                        Task {
                            await appState.extractIssuesForDisplayedTranscript()
                        }
                    }
                    .disabled(appState.isExtractingIssues(for: session))
                }
            }
        }
    }

    private func issueReviewRow(issue: ExtractedIssue, session: TranscriptSession, availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if availableWidth < 420 {
                VStack(alignment: .leading, spacing: 12) {
                    issueSelectionToggle(issue: issue, session: session)
                    issueContent(issue: issue, session: session, availableWidth: availableWidth)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    issueSelectionToggle(issue: issue, session: session)
                    issueContent(issue: issue, session: session, availableWidth: availableWidth)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func issueExportButton(destination: ExportDestination, session: TranscriptSession) -> some View {
        let isConfigured = appState.canExportIssues(from: session, to: destination)
        let isExporting = appState.isExporting(to: destination)
        let canRequestExport = appState.canRequestIssueExport(from: session)
        let setupMissing = appState.issueExportSetupMessage(for: destination) != nil

        return Button(issueExportButtonTitle(
            destination: destination,
            isConfigured: isConfigured,
            isExporting: isExporting,
            setupMissing: setupMissing
        )) {
            if isConfigured {
                Task {
                    await appState.exportSelectedIssues(from: session, to: destination)
                }
            } else if setupMissing {
                appState.openSettings()
            }
        }
        .disabled(!canRequestExport || isExporting || (!isConfigured && !setupMissing))
        .help(issueExportHelp(destination: destination, isConfigured: isConfigured, setupMissing: setupMissing))
    }

    private func issueExportButtonTitle(
        destination: ExportDestination,
        isConfigured: Bool,
        isExporting: Bool,
        setupMissing: Bool
    ) -> String {
        if isExporting {
            return "Sending to \(destination.rawValue)..."
        }

        if isConfigured {
            return "Send to \(destination.rawValue)"
        }

        if !setupMissing {
            return "Choose \(destination.rawValue) Target"
        }

        return "Set Up \(destination.rawValue)"
    }

    private func issueExportHelp(destination: ExportDestination, isConfigured: Bool, setupMissing: Bool) -> String {
        if isConfigured {
            return "Send the selected extracted issues to \(destination.rawValue)."
        }

        if !setupMissing {
            return "Choose a \(destination.rawValue) target for each selected issue."
        }

        return "Open Settings to finish \(destination.rawValue) setup."
    }

    private func issueSelectionToggle(issue: ExtractedIssue, session: TranscriptSession) -> some View {
        Toggle(
            "",
            isOn: Binding(
                get: { extractedIssue(sessionID: session.id, issueID: issue.id)?.isSelectedForExport ?? issue.isSelectedForExport },
                set: { newValue in
                    appState.setIssueSelection(newValue, issueID: issue.id, in: session.id)
                }
            )
        )
        .toggleStyle(.checkbox)
        .accessibilityLabel("Select issue \(issue.title) for export")
        .accessibilityValue((extractedIssue(sessionID: session.id, issueID: issue.id)?.isSelectedForExport ?? issue.isSelectedForExport) ? "Selected" : "Not selected")
        .accessibilityHint("Controls whether this extracted issue is included in GitHub or Jira export.")
    }

    @ViewBuilder
    private func issueContent(issue: ExtractedIssue, session: TranscriptSession, availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if availableWidth < 520 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        issueCategoryPicker(issue: issue, session: session)
                        issueSeverityPicker(issue: issue, session: session)
                    }

                    TextField(
                        "Issue title",
                        text: issueBinding(sessionID: session.id, issueID: issue.id, keyPath: \.title, fallback: issue.title)
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Issue title for \(issue.title)")

                    issueReviewBadge(issue: issue, session: session)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    issueCategoryPicker(issue: issue, session: session)
                    issueSeverityPicker(issue: issue, session: session)

                    Text("—")
                        .foregroundStyle(.secondary)

                    TextField(
                        "Issue title",
                        text: issueBinding(sessionID: session.id, issueID: issue.id, keyPath: \.title, fallback: issue.title)
                    )
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Issue title for \(issue.title)")

                    Spacer()

                    issueReviewBadge(issue: issue, session: session)
                }
            }

            HStack(alignment: .center, spacing: 10) {
                Text("Component")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(
                    "Settings > Accounts",
                    text: issueOptionalTextBinding(
                        sessionID: session.id,
                        issueID: issue.id,
                        keyPath: \.component,
                        fallback: issue.component
                    )
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Suggested component for \(issue.title)")
            }

            issueExportTargetsSection(issue: extractedIssue(sessionID: session.id, issueID: issue.id) ?? issue, session: session)

            if let timestampLabel = extractedIssue(sessionID: session.id, issueID: issue.id)?.timestampLabel ?? issue.timestampLabel {
                Text("Timestamp: \(timestampLabel)")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(.pink)
            }

            Text("Evidence: \"\((extractedIssue(sessionID: session.id, issueID: issue.id)?.evidenceExcerpt ?? issue.evidenceExcerpt).trimmingCharacters(in: .whitespacesAndNewlines))\"")
                .textSelection(.enabled)

            if let sectionTitle = extractedIssue(sessionID: session.id, issueID: issue.id)?.sectionTitle ?? issue.sectionTitle,
               !sectionTitle.isEmpty {
                Text("Section: \(sectionTitle)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            let summaryText = (extractedIssue(sessionID: session.id, issueID: issue.id)?.summary ?? issue.summary).trimmingCharacters(in: .whitespacesAndNewlines)
            if !summaryText.isEmpty && summaryText != (extractedIssue(sessionID: session.id, issueID: issue.id)?.evidenceExcerpt ?? issue.evidenceExcerpt).trimmingCharacters(in: .whitespacesAndNewlines) {
                Text("Summary: \(summaryText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(alignment: .center, spacing: 10) {
                Text("Dedup Hint")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(
                    "Stable duplicate hint",
                    text: issueDeduplicationHintBinding(
                        sessionID: session.id,
                        issueID: issue.id,
                        fallback: issue.deduplicationHint
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .accessibilityLabel("Deduplication hint for \(issue.title)")
            }

            let liveIssue = extractedIssue(sessionID: session.id, issueID: issue.id) ?? issue
            if !liveIssue.reproductionSteps.isEmpty {
                reproductionStepsSection(issue: liveIssue, session: session)
            }

            let relatedScreenshots = (extractedIssue(sessionID: session.id, issueID: issue.id) ?? issue).relatedScreenshotIDs
                .compactMap(session.screenshot(with:))
            let annotatedScreenshots = relatedScreenshots.filter {
                !liveIssue.screenshotAnnotations(for: $0.id).isEmpty
            }
            if !annotatedScreenshots.isEmpty {
                issueScreenshotAnnotationSection(
                    issue: liveIssue,
                    screenshots: annotatedScreenshots,
                    sessionID: session.id
                )
            }
            if !relatedScreenshots.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Screenshots:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(relatedScreenshots) { screenshot in
                        Button(screenshot.fileName) {
                            appState.openScreenshot(screenshot)
                        }
                        .buttonStyle(.link)
                        .accessibilityLabel("Open related screenshot \(screenshot.fileName)")
                    }
                }
            }
        }
    }

    private func issueExportTargetsSection(issue: ExtractedIssue, session: TranscriptSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export Targets")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                issueGitHubTargetEditor(issue: issue, session: session)
                issueJiraTargetEditor(issue: issue, session: session)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Export targets for \(issue.title)")
    }

    private func issueGitHubTargetEditor(issue: ExtractedIssue, session: TranscriptSession) -> some View {
        let target = effectiveGitHubTarget(for: issue)

        return IssueGitHubTargetEditor(
            issue: issue,
            target: target,
            appState: appState,
            ownerBinding: issueGitHubTargetTextBinding(
                sessionID: session.id,
                issueID: issue.id,
                keyPath: \.owner,
                fallback: target.owner
            ),
            repositoryBinding: issueGitHubTargetTextBinding(
                sessionID: session.id,
                issueID: issue.id,
                keyPath: \.repository,
                fallback: target.repository
            ),
            repositorySelection: issueGitHubRepositorySelection(issue: issue, session: session),
            labelsBinding: issueGitHubLabelsBinding(sessionID: session.id, issueID: issue.id, fallback: target.labels)
        )
    }

    private func issueJiraTargetEditor(issue: ExtractedIssue, session: TranscriptSession) -> some View {
        let target = effectiveJiraTarget(for: issue)
        let issueTypes = appState.jiraIssueTypes(for: target)

        return IssueJiraTargetEditor(
            issue: issue,
            target: target,
            issueTypes: issueTypes,
            appState: appState,
            projectKeyBinding: issueJiraProjectKeyBinding(sessionID: session.id, issueID: issue.id, fallback: target.projectKey),
            projectSelection: issueJiraProjectSelection(issue: issue, session: session),
            issueTypeNameBinding: issueJiraIssueTypeNameBinding(sessionID: session.id, issueID: issue.id, fallback: target.issueTypeName),
            issueTypeSelection: issueJiraIssueTypeSelection(issue: issue, session: session, issueTypes: issueTypes)
        )
    }

    @ViewBuilder
    private func issueScreenshotAnnotationSection(
        issue: ExtractedIssue,
        screenshots: [SessionScreenshot],
        sessionID: UUID
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Annotated Screenshots")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(screenshots) { screenshot in
                IssueScreenshotAnnotationPreview(
                    screenshot: screenshot,
                    annotations: issue.screenshotAnnotations(for: screenshot.id),
                    onUpdate: { updatedAnnotation in
                        updateScreenshotAnnotation(
                            updatedAnnotation,
                            issueID: issue.id,
                            sessionID: sessionID
                        )
                    },
                    onRemove: { annotation in
                        removeScreenshotAnnotation(
                            annotationID: annotation.id,
                            issueID: issue.id,
                            sessionID: sessionID
                        )
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func reproductionStepsSection(issue: ExtractedIssue, session: TranscriptSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reproduction Steps")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(issue.reproductionSteps.enumerated()), id: \.element.id) { index, step in
                reproductionStepEditor(
                    step: step,
                    stepIndex: index,
                    issueID: issue.id,
                    session: session
                )
            }
        }
    }

    private func reproductionStepEditor(
        step: IssueReproductionStep,
        stepIndex: Int,
        issueID: UUID,
        session: TranscriptSession
    ) -> some View {
        let liveStep = reproductionStep(sessionID: session.id, issueID: issueID, stepID: step.id) ?? step
        let referencedScreenshot = liveStep.screenshotID.flatMap(session.screenshot(with:))

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("Step \(stepIndex + 1)")
                    .font(.body.weight(.semibold))

                if let timestampLabel = liveStep.timestampLabel {
                    metadataChip(label: timestampLabel, systemImage: "clock")
                }

                if let referencedScreenshot {
                    metadataChip(label: referencedScreenshot.fileName, systemImage: "photo")
                }

                Spacer(minLength: 0)
            }

            fieldEditor(
                title: "Action",
                text: reproductionStepInstructionBinding(
                    sessionID: session.id,
                    issueID: issueID,
                    stepID: step.id,
                    fallback: liveStep.instruction
                ),
                minHeight: 56
            )

            fieldEditor(
                title: "Expected",
                text: reproductionStepOptionalTextBinding(
                    sessionID: session.id,
                    issueID: issueID,
                    stepID: step.id,
                    keyPath: \.expectedResult,
                    fallback: liveStep.expectedResult
                ),
                minHeight: 44
            )

            fieldEditor(
                title: "Actual",
                text: reproductionStepOptionalTextBinding(
                    sessionID: session.id,
                    issueID: issueID,
                    stepID: step.id,
                    keyPath: \.actualResult,
                    fallback: liveStep.actualResult
                ),
                minHeight: 44
            )

            if let referencedScreenshot {
                Button("Open Referenced Screenshot") {
                    appState.openScreenshot(referencedScreenshot)
                }
                .buttonStyle(.link)
                .accessibilityLabel("Open referenced screenshot \(referencedScreenshot.fileName) for step \(stepIndex + 1)")
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func issueCategoryPicker(issue: ExtractedIssue, session: TranscriptSession) -> some View {
        Picker(
            "",
            selection: issueBinding(sessionID: session.id, issueID: issue.id, keyPath: \.category, fallback: issue.category)
        ) {
            ForEach(ExtractedIssueCategory.allCases) { category in
                Text(category.rawValue).tag(category)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .accessibilityLabel("Issue category for \(issue.title)")
        .accessibilityValue((extractedIssue(sessionID: session.id, issueID: issue.id)?.category ?? issue.category).rawValue)
    }

    private func issueSeverityPicker(issue: ExtractedIssue, session: TranscriptSession) -> some View {
        Picker(
            "",
            selection: issueBinding(sessionID: session.id, issueID: issue.id, keyPath: \.severity, fallback: issue.severity)
        ) {
            ForEach(ExtractedIssueSeverity.allCases) { severity in
                Text(severity.rawValue).tag(severity)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .accessibilityLabel("Issue severity for \(issue.title)")
        .accessibilityValue((extractedIssue(sessionID: session.id, issueID: issue.id)?.severity ?? issue.severity).rawValue)
    }

    @ViewBuilder
    private func issueReviewBadge(issue: ExtractedIssue, session: TranscriptSession) -> some View {
        if extractedIssue(sessionID: session.id, issueID: issue.id)?.requiresReview ?? issue.requiresReview {
            Text("Needs review")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.25), in: Capsule())
                .help("AI confidence is low or the evidence is thin; review this issue before sending it.")
        }
    }

    @ViewBuilder
    private func fieldEditor(title: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: text)
                .font(.body)
                .frame(minHeight: minHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )
                .accessibilityLabel(title)
        }
    }

    private func effectiveGitHubTarget(for issue: ExtractedIssue) -> GitHubIssueExportTarget {
        issue.gitHubExportTarget ??
            appState.defaultGitHubIssueExportTarget() ??
            GitHubIssueExportTarget(labels: appState.settingsStore.githubDefaultLabelsList)
    }

    private func effectiveJiraTarget(for issue: ExtractedIssue) -> JiraIssueExportTarget {
        issue.jiraExportTarget ?? appState.defaultJiraIssueExportTarget() ?? JiraIssueExportTarget()
    }

    private func updateGitHubTarget(
        sessionID: UUID,
        issueID: UUID,
        update: (inout GitHubIssueExportTarget) -> Void
    ) {
        guard var updatedIssue = extractedIssue(sessionID: sessionID, issueID: issueID) else {
            return
        }

        var target = effectiveGitHubTarget(for: updatedIssue)
        update(&target)
        updatedIssue.gitHubExportTarget = target
        appState.updateExtractedIssue(updatedIssue, in: sessionID)
    }

    private func updateJiraTarget(
        sessionID: UUID,
        issueID: UUID,
        update: (inout JiraIssueExportTarget) -> Void
    ) {
        guard var updatedIssue = extractedIssue(sessionID: sessionID, issueID: issueID) else {
            return
        }

        var target = effectiveJiraTarget(for: updatedIssue)
        update(&target)
        updatedIssue.jiraExportTarget = target
        appState.updateExtractedIssue(updatedIssue, in: sessionID)
    }

    private func reproductionStep(sessionID: UUID, issueID: UUID, stepID: UUID) -> IssueReproductionStep? {
        extractedIssue(sessionID: sessionID, issueID: issueID)?
            .reproductionSteps
            .first(where: { $0.id == stepID })
    }

    private func issueBinding<Value>(
        sessionID: UUID,
        issueID: UUID,
        keyPath: WritableKeyPath<ExtractedIssue, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                extractedIssue(sessionID: sessionID, issueID: issueID)?[keyPath: keyPath] ?? fallback
            },
            set: { newValue in
                guard var updatedIssue = extractedIssue(sessionID: sessionID, issueID: issueID) else {
                    return
                }

                updatedIssue[keyPath: keyPath] = newValue
                appState.updateExtractedIssue(updatedIssue, in: sessionID)
            }
        )
    }

    private func issueGitHubRepositorySelection(issue: ExtractedIssue, session: TranscriptSession) -> Binding<String> {
        Binding(
            get: {
                let target = effectiveGitHubTarget(for: extractedIssue(sessionID: session.id, issueID: issue.id) ?? issue)
                if let repositoryID = target.repositoryID,
                   appState.gitHubRepositories.contains(where: { $0.repositoryID == repositoryID }) {
                    return repositoryID
                }

                return appState.gitHubRepositories.first(where: {
                    $0.owner.compare(target.owner, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame &&
                        $0.name.compare(target.repository, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                })?.repositoryID ?? ""
            },
            set: { selectedRepositoryID in
                guard let selectedRepository = appState.gitHubRepositories.first(where: { $0.repositoryID == selectedRepositoryID }) else {
                    return
                }

                updateGitHubTarget(sessionID: session.id, issueID: issue.id) { target in
                    target.repositoryID = selectedRepository.repositoryID
                    target.owner = selectedRepository.owner
                    target.repository = selectedRepository.name
                }
            }
        )
    }

    private func issueJiraProjectSelection(issue: ExtractedIssue, session: TranscriptSession) -> Binding<String> {
        Binding(
            get: {
                let target = effectiveJiraTarget(for: extractedIssue(sessionID: session.id, issueID: issue.id) ?? issue)
                if let projectID = target.projectID,
                   appState.jiraProjects.contains(where: { $0.projectID == projectID }) {
                    return projectID
                }

                return appState.jiraProjects.first(where: { $0.key == target.projectKey })?.projectID ?? ""
            },
            set: { selectedProjectID in
                guard let selectedProject = appState.jiraProjects.first(where: { $0.projectID == selectedProjectID }) else {
                    return
                }

                updateJiraTarget(sessionID: session.id, issueID: issue.id) { target in
                    target.projectID = selectedProject.projectID
                    target.projectKey = selectedProject.key
                    target.projectName = selectedProject.name
                    target.issueTypeID = ""
                    target.issueTypeName = ""
                }

                Task {
                    await appState.loadJiraIssueTypes(forProjectID: selectedProject.projectID)
                }
            }
        )
    }

    private func issueJiraIssueTypeSelection(
        issue: ExtractedIssue,
        session: TranscriptSession,
        issueTypes: [JiraIssueTypeOption]
    ) -> Binding<String> {
        Binding(
            get: {
                let target = effectiveJiraTarget(for: extractedIssue(sessionID: session.id, issueID: issue.id) ?? issue)
                if issueTypes.contains(where: { $0.id == target.issueTypeID }) {
                    return target.issueTypeID
                }

                return issueTypes.first(where: {
                    $0.name.compare(target.issueTypeName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                })?.id ?? ""
            },
            set: { selectedIssueTypeID in
                guard let selectedIssueType = issueTypes.first(where: { $0.id == selectedIssueTypeID }) else {
                    return
                }

                updateJiraTarget(sessionID: session.id, issueID: issue.id) { target in
                    target.issueTypeID = selectedIssueType.id
                    target.issueTypeName = selectedIssueType.name
                }
            }
        )
    }

    private func issueGitHubTargetTextBinding(
        sessionID: UUID,
        issueID: UUID,
        keyPath: WritableKeyPath<GitHubIssueExportTarget, String>,
        fallback: String
    ) -> Binding<String> {
        Binding(
            get: {
                let target = extractedIssue(sessionID: sessionID, issueID: issueID)
                    .map(effectiveGitHubTarget(for:)) ?? GitHubIssueExportTarget()
                return target[keyPath: keyPath].isEmpty ? fallback : target[keyPath: keyPath]
            },
            set: { newValue in
                updateGitHubTarget(sessionID: sessionID, issueID: issueID) { target in
                    target[keyPath: keyPath] = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    target.repositoryID = nil
                }
            }
        )
    }

    private func issueGitHubLabelsBinding(
        sessionID: UUID,
        issueID: UUID,
        fallback: [String]
    ) -> Binding<String> {
        Binding(
            get: {
                let target = extractedIssue(sessionID: sessionID, issueID: issueID)
                    .map(effectiveGitHubTarget(for:)) ?? GitHubIssueExportTarget(labels: fallback)
                return (target.labels.isEmpty ? fallback : target.labels).joined(separator: ", ")
            },
            set: { newValue in
                updateGitHubTarget(sessionID: sessionID, issueID: issueID) { target in
                    target.labels = parsedLabels(from: newValue)
                }
            }
        )
    }

    private func issueJiraProjectKeyBinding(
        sessionID: UUID,
        issueID: UUID,
        fallback: String
    ) -> Binding<String> {
        Binding(
            get: {
                let target = extractedIssue(sessionID: sessionID, issueID: issueID)
                    .map(effectiveJiraTarget(for:)) ?? JiraIssueExportTarget(projectKey: fallback)
                return target.projectKey.isEmpty ? fallback : target.projectKey
            },
            set: { newValue in
                updateJiraTarget(sessionID: sessionID, issueID: issueID) { target in
                    target.projectID = nil
                    target.projectName = nil
                    target.projectKey = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                }
            }
        )
    }

    private func issueJiraIssueTypeNameBinding(
        sessionID: UUID,
        issueID: UUID,
        fallback: String
    ) -> Binding<String> {
        Binding(
            get: {
                let target = extractedIssue(sessionID: sessionID, issueID: issueID)
                    .map(effectiveJiraTarget(for:)) ?? JiraIssueExportTarget(issueTypeName: fallback)
                return target.issueTypeName.isEmpty ? fallback : target.issueTypeName
            },
            set: { newValue in
                updateJiraTarget(sessionID: sessionID, issueID: issueID) { target in
                    target.issueTypeID = ""
                    target.issueTypeName = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        )
    }

    private func reproductionStepInstructionBinding(
        sessionID: UUID,
        issueID: UUID,
        stepID: UUID,
        fallback: String
    ) -> Binding<String> {
        Binding(
            get: {
                reproductionStep(sessionID: sessionID, issueID: issueID, stepID: stepID)?.instruction ?? fallback
            },
            set: { newValue in
                guard var updatedIssue = extractedIssue(sessionID: sessionID, issueID: issueID),
                      let stepIndex = updatedIssue.reproductionSteps.firstIndex(where: { $0.id == stepID }) else {
                    return
                }

                updatedIssue.reproductionSteps[stepIndex].instruction = newValue
                appState.updateExtractedIssue(updatedIssue, in: sessionID)
            }
        )
    }

    private func reproductionStepOptionalTextBinding(
        sessionID: UUID,
        issueID: UUID,
        stepID: UUID,
        keyPath: WritableKeyPath<IssueReproductionStep, String?>,
        fallback: String?
    ) -> Binding<String> {
        Binding(
            get: {
                reproductionStep(sessionID: sessionID, issueID: issueID, stepID: stepID)?[keyPath: keyPath] ?? fallback ?? ""
            },
            set: { newValue in
                guard var updatedIssue = extractedIssue(sessionID: sessionID, issueID: issueID),
                      let stepIndex = updatedIssue.reproductionSteps.firstIndex(where: { $0.id == stepID }) else {
                    return
                }

                updatedIssue.reproductionSteps[stepIndex][keyPath: keyPath] = normalizedOptionalReproductionStepText(newValue)
                appState.updateExtractedIssue(updatedIssue, in: sessionID)
            }
        )
    }

    private func issueOptionalTextBinding(
        sessionID: UUID,
        issueID: UUID,
        keyPath: WritableKeyPath<ExtractedIssue, String?>,
        fallback: String?
    ) -> Binding<String> {
        Binding(
            get: {
                extractedIssue(sessionID: sessionID, issueID: issueID)?[keyPath: keyPath] ?? fallback ?? ""
            },
            set: { newValue in
                guard var updatedIssue = extractedIssue(sessionID: sessionID, issueID: issueID) else {
                    return
                }

                updatedIssue[keyPath: keyPath] = normalizedOptionalIssueText(newValue)
                appState.updateExtractedIssue(updatedIssue, in: sessionID)
            }
        )
    }

    private func issueDeduplicationHintBinding(
        sessionID: UUID,
        issueID: UUID,
        fallback: String
    ) -> Binding<String> {
        Binding(
            get: {
                extractedIssue(sessionID: sessionID, issueID: issueID)?.deduplicationHint ?? fallback
            },
            set: { newValue in
                guard var updatedIssue = extractedIssue(sessionID: sessionID, issueID: issueID) else {
                    return
                }

                updatedIssue.deduplicationHint =
                    normalizedOptionalIssueText(newValue) ??
                    ExtractedIssue.makeDeduplicationHint(
                        title: updatedIssue.title,
                        summary: updatedIssue.summary,
                        evidenceExcerpt: updatedIssue.evidenceExcerpt
                    )
                appState.updateExtractedIssue(updatedIssue, in: sessionID)
            }
        )
    }

    private func parsedLabels(from value: String) -> [String] {
        value
            .split(whereSeparator: \.isNewline)
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func updateScreenshotAnnotation(
        _ updatedAnnotation: IssueScreenshotAnnotation,
        issueID: UUID,
        sessionID: UUID
    ) {
        guard var updatedIssue = extractedIssue(sessionID: sessionID, issueID: issueID),
              let annotationIndex = updatedIssue.screenshotAnnotations.firstIndex(where: { $0.id == updatedAnnotation.id }) else {
            return
        }

        updatedIssue.screenshotAnnotations[annotationIndex] = updatedAnnotation
        appState.updateExtractedIssue(updatedIssue, in: sessionID)
    }

    private func removeScreenshotAnnotation(
        annotationID: UUID,
        issueID: UUID,
        sessionID: UUID
    ) {
        guard var updatedIssue = extractedIssue(sessionID: sessionID, issueID: issueID) else {
            return
        }

        updatedIssue.screenshotAnnotations.removeAll { $0.id == annotationID }
        appState.updateExtractedIssue(updatedIssue, in: sessionID)
    }


    private func extractedIssue(sessionID: UUID, issueID: UUID) -> ExtractedIssue? {
        liveSession(with: sessionID)?.issueExtraction?.issues.first(where: { $0.id == issueID })
    }

    private func liveSession(with sessionID: UUID) -> TranscriptSession? {
        if appState.currentTranscript?.id == sessionID {
            return appState.currentTranscript
        }
        return transcriptStore.session(with: sessionID)
    }

    private func metadataChip(label: String, systemImage: String) -> some View {
        Label(label, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.32), in: Capsule())
    }

    private func emptyDetailState(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
