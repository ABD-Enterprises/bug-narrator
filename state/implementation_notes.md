# Implementation Notes

task_id: N5
status: ready_for_review

completed_task_ids:
- N5

CHANGED:
- Sources/BugNarrator/AppState.swift
- Sources/BugNarrator/Models/ExtractedIssue.swift
- Sources/BugNarrator/Services/ExportService.swift
- Sources/BugNarrator/Services/GitHubExportProvider.swift
- Sources/BugNarrator/Services/JiraExportProvider.swift
- Sources/BugNarrator/Services/ServiceProtocols.swift
- Sources/BugNarrator/Views/TranscriptView.swift
- Tests/BugNarratorTests/AppStateTests.swift
- Tests/BugNarratorTests/GitHubExportProviderTests.swift
- Tests/BugNarratorTests/IssueExtractionServiceTests.swift
- Tests/BugNarratorTests/JiraExportProviderTests.swift
- Tests/BugNarratorTests/TestSupport.swift
- Tests/BugNarratorTests/TranscriptionClientTests.swift
- artifacts/n5-similar-bug-detection/validate.log
- artifacts/n5-similar-bug-detection/xcodebuild-test.log
- state/artifacts.json
- state/controller.md
- state/current_task.md
- state/handoff.json
- state/tasks.json
- state/validation_report.md

DID:
- Added a pre-export similarity review flow that queries GitHub and Jira for open issues, asks OpenAI to score likely matches, and pauses export for a user decision when related bugs are found.
- Introduced review models and AppState orchestration for `export as new`, `link as related`, and `mark duplicate` actions before tracker export.
- Extended GitHub and Jira exports to include tracker-context notes for related issues and to skip duplicate ticket creation when the tester chooses an existing match.
- Added targeted coverage for the new export review state machine, tracker search requests, OpenAI similarity matching, and request-body streaming in URLProtocol-backed tests.

VALIDATED:
- ./scripts/validate.sh
- xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/bugnarrator-n5-tests test -parallel-testing-enabled NO -only-testing:BugNarratorTests/AppStateTests -only-testing:BugNarratorTests/GitHubExportProviderTests -only-testing:BugNarratorTests/JiraExportProviderTests -only-testing:BugNarratorTests/IssueExtractionServiceTests

NEXT:
- Ready for PR review on the N5 duplicate-detection slice, focusing on the pre-export review sheet, tracker search payloads, and duplicate-vs-related export decisions.
