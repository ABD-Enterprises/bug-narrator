# Testing

This is the canonical structured testing guide for BugNarrator.

Detailed companion docs:

- [QA Checklist](../QA_CHECKLIST.md)
- [Testing Notes](../TESTING_NOTES.md)
- [Release Checklist](../RELEASE_CHECKLIST.md)

## Automated Baseline

Current macOS validation baseline:

```bash
./scripts/release_smoke_test.sh
./scripts/accessibility_regression_check.sh
xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO test
xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Release CODE_SIGNING_ALLOWED=NO build
```

Current Windows workspace validation baseline on Windows:

```powershell
dotnet test windows/tests/BugNarrator.Core.Tests/BugNarrator.Core.Tests.csproj -c Debug
dotnet test windows/tests/BugNarrator.Windows.Tests/BugNarrator.Windows.Tests.csproj -c Debug
powershell -ExecutionPolicy Bypass -File windows/scripts/package-windows.ps1 -Configuration Release
powershell -ExecutionPolicy Bypass -File windows/scripts/validate-windows-package.ps1 -Runtime win-x64
```

## What Is Covered

Automated coverage currently focuses on:

- macOS session state transitions
- preserved-session retry flows when transcription is blocked by missing, invalid, or revoked OpenAI keys
- microphone and screenshot permission services
- screenshot selection and artifact creation
- review-workspace state behavior
- session library indexing, filtering, deletion, and persistence
- secure settings persistence
- transcript export and debug bundle export
- Windows core and service-layer compilation plus core tests
- Windows service-layer tests plus packaged zip validation and packaged-app smoke execution on Windows CI

## Manual Validation Still Required

Manual validation remains necessary for:

- live microphone permission prompts
- live Screen Recording prompts
- real OpenAI transcription and issue extraction
- retrying a preserved session after restoring a rejected OpenAI key in Settings
- real GitHub and Jira export
- DMG install/Gatekeeper validation
- multi-display screenshot behavior
- Windows tray/WPF runtime behavior on actual Windows

## Accessibility / 508 Validation

RR-003 established a baseline accessibility hardening pass across the live macOS app. Coverage in this phase included:

- explicit VoiceOver labels, values, and hints for previously unlabeled issue-export controls, screenshot actions, and custom session-library filters and tabs
- keyboard-first affordances in the recording controls window, including default and cancel actions
- clearer status-card and session-row summaries for assistive technology
- explicit labeling for previously title-only settings fields and hotkey assignment controls
- transient toast announcements posted through macOS accessibility notifications

Validation in this phase remained a mix of build-verified code review and static checklist review.

RR-005 completed the next runtime and hosted-site validation pass on `2026-05-12`. Coverage in that phase included:

- runtime macOS Accessibility API snapshots for Settings, Recording Controls, and Session Library surfaces, with required labels and status text passing
- published Docusaurus docs-site Lighthouse accessibility validation
- a docs-site contrast fix for the breadcrumb link color, followed by a local post-fix Lighthouse accessibility score of 100 with no failed audits
- refresh of `./scripts/accessibility_regression_check.sh` so it tracks the current AI-provider settings labels

Residual manual validation is still required for:

- hands-on VoiceOver spoken-output review across non-sampled release-candidate flows
- keyboard-only traversal of the latest release candidate

OPS-004 adds `./scripts/accessibility_regression_check.sh` as a lightweight regression tripwire. It does not replace runtime assistive-technology validation or hands-on release-candidate review; it only catches obvious code-level regressions in the most accessibility-sensitive surfaces.

## Failure Handling

When a test fails:

1. capture the failing command or manual step
2. record whether it is reproducible
3. file or update a GitHub issue if the risk or incident is material
4. link unresolved issues to the appropriate GitHub work item or remediation issue

## Related Docs

- [Product Spec](../architecture/product-spec.md)
- [Development Setup](../development/setup.md)
- [Release Process](../release/release-process.md)
- [Windows Validation Checklist](../../windows/docs/WINDOWS_VALIDATION_CHECKLIST.md)
