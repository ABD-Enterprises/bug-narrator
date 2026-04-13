# Implementation Notes

task_id: N2
status: ready_for_review

CHANGED:
- Sources/BugNarrator/Models/ExtractedIssue.swift
- Sources/BugNarrator/Services/GitHubExportProvider.swift
- Sources/BugNarrator/Services/IssueExtractionService.swift
- Sources/BugNarrator/Services/JiraExportProvider.swift
- Sources/BugNarrator/Views/TranscriptView.swift
- Tests/BugNarratorTests/GitHubExportProviderTests.swift
- Tests/BugNarratorTests/IssueExtractionServiceTests.swift
- Tests/BugNarratorTests/JiraExportProviderTests.swift

DID:
- Added structured reproduction-step data to extracted issues, with per-step instruction, expected result, actual result, timestamp, and screenshot reference persistence.
- Extended the issue-extraction prompt/parser so OpenAI returns reproduction steps tied to narration timecodes and screenshot file names, with issue-level reference fallback when a step omits one.
- Rendered reproduction steps in the review workspace with editable action, expected, and actual fields plus visible timestamp and screenshot references.
- Included reproduction steps and step references in both GitHub and Jira export payloads so the generated issue tracker tickets carry the same reviewable repro details.
- Normalized optional reproduction-step edits so expected and actual text is trimmed before persistence, preventing accidental whitespace from leaking into exports.

VALIDATED:
- ./scripts/validate.sh
- xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/bugnarrator-n2-tests test -only-testing:BugNarratorTests/IssueExtractionServiceTests -only-testing:BugNarratorTests/GitHubExportProviderTests -only-testing:BugNarratorTests/JiraExportProviderTests
- xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO -only-testing:BugNarratorTests/ReviewWorkspaceTests test

NEXT:
- Confirm the PR review thread about reproduction-step whitespace is resolved by the pushed branch update.
