# Testing Notes

Structured counterpart: [docs/testing/testing.md](testing/testing.md)

## Automated Validation

Use these commands as the current release-readiness baseline:

- `./scripts/release_smoke_test.sh`
- `xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO test`
- `xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Release CODE_SIGNING_ALLOWED=NO build`
- `./scripts/build_dmg.sh`

For public-release validation, also run the signed and notarized DMG workflow documented in [Distribution.md](Distribution.md).

## What The Tests Cover

- recording state transitions, duplicate-start protection, repeated sessions, and single-instance behavior
- microphone preflight, denied/restricted handling, and local-build permission recovery messaging
- screenshot region selection, Screen Recording preflight, screenshot metadata creation, and repeated capture protection
- screenshot-driven timeline event generation and review-workspace tab behavior
- issue extraction parsing, empty-result fallback, and export selection state
- GitHub and Jira export validation plus partial-success failure reporting
- session-library filtering, search, sorting, deletion, and persistence recovery
- transcript export, session bundle export, and debug bundle export
- secure settings persistence, token masking, and optional hotkey assignment behavior
- About/changelog/support/documentation link wiring and version/build metadata formatting

## Manual Validation Still Required

- live microphone permission prompts and denied-permission recovery
- end-to-end transcription against the real OpenAI API
- real screenshot capture behavior with macOS Screen Recording permission
- real GitHub export against a repository you control
- real Jira Cloud export against a project you control
- opening the generated DMG in Finder and validating the drag-to-Applications flow
- visual review of the session library layout, compact review workspace, and menu bar UX
- live multi-display screenshot capture with Screen Recording permission granted on the release build

## Notes

- The automated suite does not exercise the live SwiftUI UI layer or AVFoundation microphone pipeline.
- Screenshot capture now uses ScreenCaptureKit on the app's supported macOS 14+ target. Permission prompting still relies on the macOS Screen Recording TCC helpers so the app can explain recovery steps before a capture attempt fails.
- The unsigned build and test commands are intentional so the repo does not depend on a personal Apple signing team in project defaults.
- If local Xcode or DerivedData builds are cluttering Launch Services or TCC during manual permission testing, run `./scripts/cleanup_local_build_apps.sh` so only the installed `/Applications/BugNarrator.app` remains in normal tester paths.
