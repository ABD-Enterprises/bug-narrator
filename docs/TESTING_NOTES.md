# Testing Notes

## Automated Validation

- Build command run: `xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO build`
- Build result: passed
- Packaging command run: `./scripts/build_dmg.sh`
- Packaging result: passed
- Packaging validation: generated `dist/BugNarrator-v1.0-macOS.dmg` and `dist/BugNarrator-macOS.dmg`, mounted the DMG successfully, and verified it contains `BugNarrator.app` plus an `Applications` shortcut
- Test command run: `xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO test`
- Test result: passed
- Test count: 69

## What The Tests Cover

- core recording state transitions and repeated back-to-back sessions
- missing API key and denied microphone preflight handling
- duplicate start and duplicate stop protection
- marker insertion and screenshot capture state updates
- automatic issue extraction after transcription
- export preflight validation and successful GitHub export dispatch
- GitHub request construction and repository/auth failure mapping
- Jira request construction and validation failure mapping
- issue extraction response mapping into structured draft issues
- session-library date bucket filtering, search, empty states, and sort order
- transcript history persistence, deletion, and 500-session retention
- transcript-store rollback on persistence failure and recovery from backup history files
- session-artifact path sanitization and safe managed-directory cleanup
- secure settings persistence, masking, and token removal
- transcription request construction and OpenAI error mapping
- About window/changelog action wiring and external project-link dispatch
- version/build metadata formatting and changelog highlight parsing
- support window callback wiring and PayPal support-page URL dispatch
- partial-success export failure reporting for GitHub and Jira issue creation
- screenshot open failure handling that preserves app-state truthfulness during active sessions

## Manual Validation Still Required

- live microphone permission prompts and denied-permission recovery
- end-to-end transcription against the real OpenAI API
- real screenshot capture behavior with macOS Screen Recording permission
- real GitHub export against a repository you control
- real Jira Cloud export against a project you control
- opening the generated DMG in Finder and validating the drag-to-Applications flow
- visual review of the session library layout and menu bar UX

## Notes

- The automated suite does not exercise the live SwiftUI UI layer or AVFoundation microphone pipeline.
- Screenshot capture still builds with one deprecation warning for `CGWindowListCreateImage`; migrating to ScreenCaptureKit remains future work.
- The unsigned build and test commands are intentional so the repo does not depend on a personal Apple signing team in project defaults.
