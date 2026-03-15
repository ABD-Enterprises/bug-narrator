# Changelog

## Unreleased

## 1.0.17 - 2026-03-15

- Fixed the signed DMG packaging flow so BugNarrator keeps the macOS audio-input entitlement when the release app is re-signed for Developer ID distribution.
- Added the BugNarrator entitlements file to the project so the shipped app retains microphone capability in notarized public builds instead of losing it during packaging.

## 1.0.16 - 2026-03-15

- Fixed the signed app's microphone prompt path again by using macOS media-capture authorization to trigger the system microphone prompt, then resolving the final state from both app-level and capture-device permission APIs.
- Improved microphone permission recovery when one macOS permission API stayed stale or disagreed with the other after resets or repeated local testing.

## 1.0.15 - 2026-03-15

- Fixed another microphone permission recovery bug where BugNarrator could stay stuck in a blocked state after a TCC reset or stale app-level permission read instead of refreshing and retrying the macOS prompt path.
- Added regression coverage for blocked microphone states that refresh into a grant during recording preflight.
- Clarified the public repo policy so BugNarrator is not currently accepting outside code contributions or pull requests.

## 1.0.14 - 2026-03-15

- Fixed a microphone permission state bug where BugNarrator could mix the older capture-device authorization API with the modern app-level microphone permission API and incorrectly conclude that access was denied before macOS had shown the prompt.
- Switched microphone prompting and preflight state on macOS 14+ to the modern app-level permission API so first-run and post-reset permission requests behave more reliably for the signed app.

## 1.0.13 - 2026-03-15

- Fixed a microphone permission prompt path bug for the menu bar app so BugNarrator now activates itself before requesting microphone access from macOS.
- Improved first-run and post-reset microphone behavior for the signed app when macOS had a mismatched not-determined vs denied permission state and was failing to surface the system prompt.

## 1.0.12 - 2026-03-15

- Fixed a microphone permission regression where BugNarrator could enter a fake recording state and produce silent sessions even though macOS still had microphone access blocked.
- Tightened recording preflight so denied or restricted microphone permission now blocks recording immediately instead of letting a recorder activation probe override the system privacy state.
- Added regression coverage to keep blocked microphone states from starting a session or silently recording nothing.

## 1.0.11 - 2026-03-15

- Simplified the recording controls window by removing the standalone marker button and making screenshot capture the primary way to mark important moments during a session.
- Tightened the right-hand review workspace so the header, actions, tabs, and content use less vertical space and start reading immediately.
- Removed the separate `Markers` tab from the review workspace while keeping older marker-only sessions readable in the transcript timeline.
- Unified screenshot and marker timeline entries so screenshot captures create one cleaner combined review event instead of duplicate marker and screenshot rows.
- Removed built-in hotkey defaults so recording and screenshot shortcuts now start unassigned until the user explicitly chooses them.
- Removed shortcut suggestions and the `Default` hotkey button, and changed duplicate-assignment behavior so conflicts are rejected with a clear message instead of silently overriding another action.
- Removed the obsolete standalone marker hotkey runtime and settings path, and now clear any legacy stored marker shortcut during settings load.
- Polished the drag-to-select screenshot overlay with clearer visual feedback, a lightweight hint, and a cleaner cancellation path.
- Refined the `Screenshots` tab so captured images show cleaner thumbnails, timestamps, linked markers, and direct-open behavior.
- Replaced full-display screenshot capture with a drag-to-select region overlay so BugNarrator saves only the area the tester chooses.
- Kept screenshot captures attached to the active session with the same timestamp and automatic marker behavior, while treating `Esc` and zero-size selections as clean cancellations.
- Added screenshot capture regression coverage for region cropping, off-display selections, and cancelled selections.
- Refreshed the release and QA docs to match the compact screenshot-driven workflow, and revalidated the current workspace with passing debug tests, a clean Release build, and a successful local DMG package build.

## 1.0.10 - 2026-03-15

- Centralized microphone and screenshot permission preflight so recording and screenshot actions validate permissions and real capture capability before starting.
- Fixed a false-denied microphone path where recording preflight could pass but the recorder immediately re-ran permission checks and blocked the same session start anyway.
- Added screenshot-specific preflight so denied Screen Recording access no longer leaks into the main recording flow.
- Added targeted automated coverage for microphone preflight, screenshot preflight, stale permission recovery, and capture-setup failures.

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
