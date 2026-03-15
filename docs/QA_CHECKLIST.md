# BugNarrator QA Checklist

## Setup

- Build the DMG with `./scripts/build_dmg.sh`.
- Open the generated DMG and confirm it shows `BugNarrator.app` plus the `Applications` shortcut in a clean drag-to-Applications Finder layout.
- Confirm the mounted DMG shows the branded BugNarrator volume icon on the desktop and in Finder.
- Drag `BugNarrator.app` to `Applications` and launch that installed copy once.
- Build and run `BugNarrator` from Xcode.
- Confirm the menu bar item appears after launch.
- Launch BugNarrator a second time while it is already running and confirm the existing instance becomes active instead of creating a second menu bar item.
- Confirm a double-launch attempt does not produce duplicate recording state, duplicate export work, or duplicate menu bar icons.
- Confirm the first launch does not trigger an unexpected Keychain or admin-style credential prompt before you open Settings or start a key-dependent action.
- Confirm the menu bar explains that the app requires the user's own OpenAI API key.
- Open Settings and verify the onboarding copy explains that OpenAI usage may incur charges.
- Verify the OpenAI API key can be entered, remains masked, and shows a secure-storage note.
- Verify `Validate Key` reports success for a working key and a clear error for a bad key.
- Verify `Remove Key` clears the stored OpenAI key.
- Verify GitHub and Jira tokens remain masked and can be removed.
- Verify `Copy Debug Info` copies app version, macOS version, architecture, active models, and session ID without any credentials.
- Verify `Export Debug Bundle` writes a local bundle containing `system-info.json`, `app-version.txt`, `macos-version.txt`, `recent-log.txt`, and `session-metadata.json`.
- Verify the exported debug bundle does not contain API keys, GitHub tokens, Jira tokens, or raw credentials.
- Confirm microphone permission is requested on the first recording attempt if it has not already been granted.
- Confirm screenshot capture prompts for Screen Recording permission if macOS requires it.

## About And Product Info

- Open `About BugNarrator` from the menu bar.
- Verify the About window opens and displays the app name, tagline, version, and build information.
- Verify the GitHub repository action opens the project repository in the default browser.
- Verify the documentation action opens the hosted `docs/UserGuide.md` page in the default browser.
- Verify the report issue action opens the GitHub new-issue page.
- Verify the support development action opens the support window.
- Verify the support window shows a single PayPal support action.
- Verify the support button opens the configured PayPal donation page in the default browser.
- Open `What’s New` from the menu bar or the About window.
- Verify the changelog window opens and displays the bundled `CHANGELOG.md` content.
- Verify `Check for Updates` opens the GitHub releases page.
- Confirm there are no dead or mislabeled menu items in the project-info section.

## Product Polish And UX

- Verify the menu bar window feels clearly grouped into status, session controls, recent-session access, and product-info sections.
- Verify the primary session action is always visually obvious in Idle, Recording, Transcribing, Success, and Error states.
- Verify long status and error messages remain readable without awkward clipping.
- Verify the recording state feels unmistakable through the red indicator, elapsed timer, and control placement.
- Verify the session library reads like an archive of review sessions rather than a plain transcript dump.
- Verify the detail pane makes the distinction between raw transcript, review summary, screenshots, and extracted issues easy to understand.
- Verify Settings feels intentionally grouped and not like an unstructured admin panel.
- Verify About, documentation, changelog, issue reporting, and support surfaces feel visually and tonally consistent with the rest of the app.

## Download And Install Experience

- Verify the README `Download` section is easy to find near the top.
- Verify the README links to the release page and the expected DMG download path.
- Verify the README `Support Development` section is visible near the top.
- If testing a published release, confirm the DMG download link resolves to the expected artifact.
- Verify the install steps in `README.md` and `docs/UserGuide.md` match the actual DMG flow.

## Core Workflow

- Start a feedback session from the menu bar.
- Verify the recording controls window opens immediately and no duplicate control windows appear if you click `Start Feedback Session` again.
- Verify the status changes to `Recording`.
- Verify the red recording indicator and elapsed timer appear and continue updating.
- Switch between apps, click around, and keep speaking for at least 15 seconds.
- Insert at least two markers during the session.
- Capture at least one screenshot during the session.
- Stop the session.
- Verify the recording controls window stays open after the session stops and only closes when you explicitly close it.
- Verify the status changes to `Transcribing` and then `Success`.
- Verify the session library window opens with the completed transcript selected.
- Verify the transcript is copied to the clipboard when auto-copy is enabled.
- Verify the new session appears in the session library immediately after the run.

## Session Library Browsing

- Verify the left sidebar shows `Today`, `Yesterday`, `Last 7 Days`, `Last 30 Days`, `All Sessions`, and `Custom Date Range`.
- Verify each sidebar filter shows a session count that changes as sessions are added or removed.
- Switch between `Today`, `Yesterday`, `Last 7 Days`, `Last 30 Days`, and `All Sessions` and confirm the session list updates without UI lag.
- With a larger history set available, switch filters rapidly and confirm the list and counts stay responsive without obvious hangs or stale selections.
- Set a custom start date and end date and confirm only sessions in that range are listed.
- Enter a search term that matches transcript text and verify the list narrows to matching sessions.
- Enter a search term that matches extracted issue summary text and verify the list narrows to matching sessions.
- With a larger history set available, search for a term that matches many sessions and confirm results update quickly enough for normal use.
- Change sorting to `Oldest First` and confirm the list order reverses correctly.
- Select a session from the list and verify the detail pane updates in place without opening a separate popup.
- Rapidly switch between several different sessions and verify the detail pane updates cleanly without visual thrash, stale transcript content, or mismatched counts.
- Verify the detail pane keeps access to raw transcript, markers, screenshots, extracted issues, and export actions.
- Verify an empty state appears for no sessions yet, no sessions in a filter, no sessions in a custom date range, and no search results.

## Marker And Screenshot Workflow

- Insert a marker during recording and verify it appears in the `Markers` tab with the correct time.
- Capture a screenshot during recording and verify it appears in the `Screenshots` tab.
- If the screenshot is near a marker, verify the screenshot shows a linked marker when practical.
- Open a captured screenshot from the review window and verify Finder reveals the file.
- Export a session bundle and verify `transcript.txt`, `transcript.md`, `summary.md`, and the `screenshots` folder are present.
- Export a debug bundle during or after a session and verify `session-metadata.json` reflects the right session ID and counts without raw transcript content.

## Session Deletion

- Select a saved session and delete it from the library toolbar.
- Verify a confirmation dialog appears before permanent deletion.
- Confirm the deleted session disappears from the list immediately after confirmation.
- Verify sidebar counts update after deletion.
- Verify the detail pane switches to the next available session or an empty state.
- Delete a session from the row context menu and verify the same behavior.
- Delete a session that contains screenshots and verify the app warns that local screenshots will also be removed.
- Verify exported files outside BugNarrator remain untouched after deleting the session.
- After deleting the selected session, verify GitHub and Jira export actions are no longer available for that removed session state.

## Issue Extraction Workflow

- Open a completed session and run `Extract Issues`.
- Verify the `Extracted Issues` tab shows a summary, guidance note, and categorized draft issues.
- Verify each issue preserves transcript evidence and timestamp context when available.
- Edit an extracted issue title, summary, or category and confirm the change persists when you switch away and back.
- Select and deselect issues for export and verify the selection state persists.
- Enable automatic issue extraction in Settings and confirm a later session runs extraction automatically after transcription.

## GitHub Export

- Configure a GitHub token, repository owner, and repository name in Settings.
- Verify GitHub export buttons stay disabled until configuration is complete.
- Export one selected issue to GitHub and confirm a new issue appears in the target repository.
- Export multiple selected issues and confirm each selected issue becomes a separate GitHub issue.
- Verify the GitHub issue body contains transcript evidence and timestamp references.
- Use a bad token or repository name and verify BugNarrator shows a clear export error.
- Force one issue export to succeed and a later one to fail, then verify BugNarrator reports partial success instead of a generic failure.

## Jira Export

- Configure Jira Cloud URL, email, API token, project key, and issue type in Settings.
- Verify Jira export buttons stay disabled until configuration is complete.
- Export one selected issue to Jira and confirm a new issue appears in the configured project.
- Export multiple selected issues and confirm each selected issue becomes a separate Jira issue.
- Verify the Jira issue description contains transcript evidence and timestamp references.
- Use a bad token, bad project key, or invalid issue type and verify BugNarrator shows a clear export error.
- Force one issue export to succeed and a later one to fail, then verify BugNarrator reports partial success instead of a generic failure.

## Repeated Session Regression

- Complete a full start-record-stop-transcribe cycle with markers and screenshots.
- Start a second session without restarting the app.
- Complete a second full cycle and verify the new session appears first in the session library when sorted newest-first.
- Repeat once more with automatic issue extraction enabled.
- Verify the app never gets stuck in `Recording`, `Transcribing`, or export-in-progress state.
- After several sessions exist, relaunch BugNarrator while it is already running and confirm the existing session library remains intact and only one menu bar instance is visible.

## Failure Cases

- Remove the OpenAI API key and attempt to start a session.
  Expected: recording can still start after microphone permission is granted, but the app explains that transcription will require the user's own OpenAI API key before the session can be finished with OpenAI features.
- Start recording, remove the OpenAI API key from Settings, then stop the session.
  Expected: the app fails gracefully, explains that the key is missing, and remains usable for the next session.
- Deny microphone permission and attempt to start a session.
  Expected: recording does not start, the error explains how to re-enable access in System Settings, and `Open Microphone Settings` opens the expected privacy pane or a safe fallback.
- Capture a screenshot without Screen Recording permission.
  Expected: recording continues, BugNarrator shows a screenshot-specific error, and `Open Screen Recording Settings` opens the expected privacy pane or a safe fallback.
- Delete or move a saved screenshot file outside the app, then open it from the session detail view.
  Expected: BugNarrator explains that the local screenshot file is no longer available instead of failing silently.
- Disconnect networking or force a timeout during transcription.
  Expected: transcription ends in a clear timeout or API error state and the app returns to a usable state.
- Use an invalid OpenAI API key.
  Expected: transcription or issue extraction ends in a clear invalid-key error, Settings opens, and the menu bar offers a direct `Open Settings` recovery action.
- Simulate a local history write failure after a successful transcription if practical.
  Expected: the transcript window still opens, the completed session remains available as an unsaved session, screenshots remain accessible, and `Save to History` can be retried later after storage is fixed.
- Cancel an active recording.
  Expected: discard confirmation appears first, then the session returns to `Idle` with no stale timer.

## Persistence And Cleanup

- Create several sessions, quit the app, relaunch, and verify the session library reloads correctly.
- If you can simulate a corrupted session-history file, verify the app still recovers from the backup copy instead of showing an empty library.
- Delete a session with screenshots and verify the managed screenshot folder is removed.
- Confirm deleting one session does not remove unrelated files or folders outside BugNarrator's managed session-assets directory.

## Settings Regression

- Change auto-copy, auto-save, and auto-extract toggles and verify the next session follows the new values.
- Change the start, stop, marker, and screenshot hotkeys and verify the new shortcuts are registered.
- Assign the same shortcut to two different actions and verify BugNarrator disables the older conflicting action instead of keeping both active.
- While recording, verify secret fields are disabled.
- Enable Debug Mode and confirm temporary audio files are retained after a completed or cancelled session.
- Disable Debug Mode and confirm temporary audio files are cleaned up after a completed or cancelled session.
- Enable Debug Mode and verify recent diagnostics logs become more verbose than they are in the default mode.
