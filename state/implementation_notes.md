# Implementation Notes

task_id: N3-H1
status: ready_for_review

completed_task_ids:
- N3-H1

CHANGED:
- Sources/BugNarrator/Models/ExtractedIssue.swift
- Sources/BugNarrator/Services/IssueExtractionService.swift
- Tests/BugNarratorTests/IssueExtractionServiceTests.swift
- state/artifacts.json
- state/controller.md
- state/current_task.md
- state/tasks.json
- state/validation_report.md

DID:
- Pinned deduplication-hint normalization to `en_US_POSIX` so identical issue text hashes consistently across machines and user locales.
- Moved the severity keyword lists in `IssueExtractionService` to static constants so extraction inference reuses them instead of allocating on every parse.
- Added a regression test that exercises locale-sensitive casing and verifies the deduplication hash matches fixed-locale normalization.

VALIDATED:
- ./scripts/validate.sh
- xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/bugnarrator-n3h1-tests test -only-testing:BugNarratorTests/IssueExtractionServiceTests -only-testing:BugNarratorTests/GitHubExportProviderTests -only-testing:BugNarratorTests/JiraExportProviderTests

NEXT:
- Ready for PR review on the N3-H1 hardening slice.
