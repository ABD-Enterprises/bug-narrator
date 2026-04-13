# Implementation Notes

task_id: N3
status: ready_for_review

CHANGED:
- Sources/BugNarrator/Models/ExtractedIssue.swift
- Sources/BugNarrator/Models/TranscriptSession.swift
- Sources/BugNarrator/Services/GitHubExportProvider.swift
- Sources/BugNarrator/Services/IssueExtractionService.swift
- Sources/BugNarrator/Services/JiraExportProvider.swift
- Sources/BugNarrator/Views/TranscriptView.swift
- Tests/BugNarratorTests/GitHubExportProviderTests.swift
- Tests/BugNarratorTests/IssueExtractionServiceTests.swift
- Tests/BugNarratorTests/JiraExportProviderTests.swift

DID:
- Added severity, suggested component, and stable deduplication-hint fields to extracted issues, with persistence defaults for older saved sessions.
- Extended issue extraction so OpenAI can return severity/component metadata, while local fallbacks infer severity from narration content, reuse section titles as component context, and generate deduplication hashes when hints are missing.
- Rendered editable severity, component, and deduplication fields in the review workspace alongside the existing issue editor.
- Included the new classification metadata in review markdown plus GitHub and Jira export payloads.
- Added targeted tests that cover structured parsing, fallback inference, and export formatting for the new classification metadata.

VALIDATED:
- ./scripts/validate.sh
- xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/bugnarrator-n3-tests test -only-testing:BugNarratorTests/IssueExtractionServiceTests -only-testing:BugNarratorTests/GitHubExportProviderTests -only-testing:BugNarratorTests/JiraExportProviderTests -only-testing:BugNarratorTests/TranscriptExporterTests -only-testing:BugNarratorTests/ReviewWorkspaceTests

NEXT:
- Ready for PR review on the N3 issue-classification slice.
