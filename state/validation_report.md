# Validation Report

task_id: N2
result: passed
summary: Runtime guardrails and the targeted BugNarrator extraction/export macOS tests passed for the N2 reproduction-step slice.

artifacts:
- artifacts/n2-reproduction-steps/validate.log
- artifacts/n2-reproduction-steps/xcodebuild-test.log

commands:
- ./scripts/validate.sh -> PASS
- xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/bugnarrator-n2-tests test -only-testing:BugNarratorTests/IssueExtractionServiceTests -only-testing:BugNarratorTests/GitHubExportProviderTests -only-testing:BugNarratorTests/JiraExportProviderTests -> PASS
