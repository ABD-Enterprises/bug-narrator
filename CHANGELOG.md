# Changelog

## Unreleased

## 1.0.9 - 2026-03-15

- Added a dedicated microphone permission service with structured recording preflight, clearer denied vs restricted vs unavailable states, and better local-testing guidance for unsigned Xcode builds.
- Fixed review-workspace tab selection so switching between sessions with different content does not leave the right-hand pane on an invalid or stale tab.
- Switched screenshot previews in the review workspace to cached thumbnails instead of repeatedly decoding full-size images, which reduces lag and memory waste in screenshot-heavy sessions.
- Fixed a single-instance regression that could terminate the XCTest app host when another BugNarrator copy was already running during local validation.
- Added targeted automated coverage for review-workspace state rules, session-bundle export contents, and the XCTest single-instance bypass path.

## 1.0.8 - 2026-03-15

- Simplified the menu bar so recording actions now live only in the BugNarrator controls window, with the menu focusing that window instead of duplicating start or stop actions.
- Reduced the controls window size, preserved its position between launches, and stopped it from jumping across the screen when starting a session or capturing screenshots.
- Added clearer microphone recovery guidance for local unsigned builds so testing from DerivedData explains why macOS may ask for permission again for different app bundle paths.

## 1.0.7 - 2026-03-15

- Replaced the floating recording HUD with a persistent recording controls window and configurable start, stop, marker, and screenshot shortcuts.
- Added structured local diagnostics, debug bundle export, and copyable debug info for safer GitHub issue reporting without exposing credentials.
- Added single-instance enforcement plus session-library and detail-view performance improvements for larger local histories.
- Polished the menu bar, settings, session review workspace, and product copy to make BugNarrator feel more focused and easier to use daily.
- Upgraded the DMG packaging flow so the mounted disk uses the BugNarrator icon and opens to a cleaner drag-to-Applications Finder window.
- Removed the duplicate microphone recovery prompt from the menu bar while keeping the direct microphone settings recovery action.

## 1.0.6 - 2026-03-14

- Added a compact floating recording HUD so marker and screenshot controls stay available without reopening the menu bar window.
- Changed screenshot capture to auto-insert a marker so screenshots stay anchored to the session timeline.
- Updated the start-session flow so recording can begin without an OpenAI API key, while still requiring the key before transcription.

## 1.0.5 - 2026-03-14

- Rebuilt and republished BugNarrator from the current stabilized main branch as a fresh signed, notarized, and stapled macOS release.

## 1.0.4 - 2026-03-14

- Fixed microphone permission detection on macOS 14+ so BugNarrator reads the app's actual granted microphone state and no longer stays blocked after access has been enabled in System Settings.

## 1.0.3 - 2026-03-14

- Fixed a microphone-permission recovery bug where BugNarrator could keep showing a stale “microphone denied” error even after access had been granted in System Settings.

## 1.0.2 - 2026-03-14

- Migrated screenshot capture from the deprecated CoreGraphics screenshot path to ScreenCaptureKit on macOS 14+, while preserving session associations, marker proximity, and screenshot-specific permission recovery.
- Added direct recovery guidance and an `Open Microphone Settings` action when microphone permission is denied.
- Updated the menu bar status card to wrap longer error text and expand for recovery messaging instead of truncating it.
- Hardened post-transcription persistence so a completed transcript stays open as an unsaved session if local history storage fails after transcription.
- Updated the session library to prefer the latest in-memory session snapshot when persistence falls behind, preventing stale issue edits and summaries from disappearing out of the detail view.
- Prevented GitHub and Jira exports from running against deleted or stale sessions and added date-bucket regression coverage around midnight in local timezones.
- Hardened the DMG packaging script to verify branded icon resources, DMG contents, and public-release validation steps before publishing.
- Added regression coverage for deferred interactive secret loading and the menu bar status presentation rules behind the permission and error fixes.

## 1.0.1 - 2026-03-14

- Fixed the app icon pipeline so BugNarrator ships with branded app icon assets instead of a generic fallback.
- Simplified Support Development to a single PayPal action and aligned the app UI, documentation, and tests with that flow.
- Fixed the initial install experience by avoiding an unexpected credential prompt on first launch before the user explicitly uses a key-dependent feature.

## 1.0.0 - 2026-03-14

- Renamed the app to BugNarrator and aligned the product identity across the project.
- Added a scalable session library with date filters, search, sorting, and session deletion.
- Added markers, screenshot capture, extracted issues, and GitHub or Jira export workflows.
- Added a polished About BugNarrator window, project links, support-development action, and in-app changelog viewer.
- Added a repeatable DMG packaging workflow, release documentation, and clearer download or support guidance for end users.

## 0.9.0 - 2026-03-13

- Added transcript capture, local session history, and clipboard copy after transcription.
- Added OpenAI API key management with Keychain storage and validation.
- Added issue extraction and structured export foundations for developer tooling.

## 0.8.0 - 2026-03-12

- Added the initial macOS menu bar recording workflow for narrated software testing sessions.
- Added background microphone capture, Whisper transcription, and a transcript review window.
