# Validation Report

task_id: N5
result: passed
summary: Runtime guardrails plus the targeted duplicate-detection, export provider, and similarity-review macOS tests passed for the N5 similar bug detection slice.

artifacts:
- artifacts/n5-similar-bug-detection/validate.log
- artifacts/n5-similar-bug-detection/xcodebuild-test.log

commands:
- ./scripts/validate.sh -> PASS
- xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/bugnarrator-n5-tests test -parallel-testing-enabled NO -only-testing:BugNarratorTests/AppStateTests -only-testing:BugNarratorTests/GitHubExportProviderTests -only-testing:BugNarratorTests/JiraExportProviderTests -only-testing:BugNarratorTests/IssueExtractionServiceTests -> PASS
