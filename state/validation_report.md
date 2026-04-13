# Validation Report

task_id: N3
result: passed
summary: Runtime guardrails plus the targeted BugNarrator extraction/export/review macOS tests passed for the N3 issue-classification slice.

artifacts:
- artifacts/n3-issue-classification/validate.log
- artifacts/n3-issue-classification/xcodebuild-test.log

commands:
- ./scripts/validate.sh -> PASS
- xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/bugnarrator-n3-tests test -only-testing:BugNarratorTests/IssueExtractionServiceTests -only-testing:BugNarratorTests/GitHubExportProviderTests -only-testing:BugNarratorTests/JiraExportProviderTests -only-testing:BugNarratorTests/TranscriptExporterTests -only-testing:BugNarratorTests/ReviewWorkspaceTests -> PASS
