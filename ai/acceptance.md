# Acceptance Criteria

## Global acceptance rules

- GitHub PR review is the source of truth for acceptance
- Required GitHub checks pass
- No unrelated file churn
- No docs-only or state-only commit
- Changes stay within current task scope unless required for the fix
- CI or review failure continues the same task through `review_failed_fix_required`

## Review-ready checklist

- The working branch is pushed or ready to push
- A pull request is open or ready to update
- Relevant local preflight validation already passed
- GitHub CI is running or has run
- GitHub review feedback is collected, including Gemini Code Assist on GitHub if configured
- Review remediation, if needed, is tracked through `review_failed_fix_required`

## Per-task acceptance

### T1

- the branch-local state files match PR #5 and the current review loop
- runtime guardrails passes against base `9a0048fc6397f1be3086b3753b2afa4a912399d2`
- targeted `SettingsStore` validation evidence is present on the branch
- the review handoff can proceed through GitHub PR and CI

Validation commands:

- `git diff --check`
- `./scripts/validate.sh 9a0048fc6397f1be3086b3753b2afa4a912399d2`
- `xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/bugnarrator-settings-tests test -only-testing:BugNarratorTests/SettingsStoreTests`

### T2

- the reported PR failure is no longer reproducible
- the related local validation has been rerun
- the follow-up review feedback can be collected through GitHub PR and CI
- only a planning or design failure routes the task back to Claude

Validation commands:

- `./scripts/validate.sh 9a0048fc6397f1be3086b3753b2afa4a912399d2`
- `xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO -derivedDataPath /tmp/bugnarrator-settings-tests test -only-testing:BugNarratorTests/SettingsStoreTests`
