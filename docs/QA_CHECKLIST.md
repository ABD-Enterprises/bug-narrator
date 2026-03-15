# BugNarrator QA Checklist

## Setup

- For manual recording-based QA, ask testers to follow the [Tester Narration Guide](UserGuide.md#tester-narration-guide) so transcripts and extracted issues include clear repro context.
- Build the DMG with `./scripts/build_dmg.sh`.
- Run `./scripts/release_smoke_test.sh` before a release candidate so the current app still passes the core automated validation path.
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
- Confirm recording does not enter a fake `Recording` state if microphone preflight fails before capture starts.
- Confirm a denied microphone state, a restricted microphone state, and an audio-capture-unavailable state each show distinct guidance instead of the same generic error.
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

- During any narrated manual test, verify the tester is stating environment, goal, expected behavior, actual behavior, and session-ending outcome clearly enough for the transcript to stand alone.
- Start a feedback session from the menu bar.
- Verify the recording controls window opens immediately and no duplicate control windows appear if you click `Start Recording` again.
- Verify the status changes to `Recording`.
- Verify the red recording indicator and elapsed timer appear and continue updating.
- Switch between apps, click around, and keep speaking for at least 15 seconds.
- Capture at least one screenshot during the session.
- Verify screenshot capture opens a dimmed drag-selection overlay with a crosshair cursor instead of immediately saving the full desktop.
- Drag-select a region and verify only that region is saved to the session.
- Press `Esc` during screenshot selection and verify the capture cancels without creating a screenshot or ending the recording.
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
- Select a session with `Extracted Issues` or `Summary`, switch to that tab, then select a session without those sections and verify the review workspace falls back cleanly instead of staying on a blank or stale tab.
- Verify the detail pane keeps access to the transcript timeline, screenshots, extracted issues, summary, and export actions.
- Verify an empty state appears for no sessions yet, no sessions in a filter, no sessions in a custom date range, and no search results.

## Screenshot Timeline Workflow

- Capture a screenshot during recording and verify it appears in the `Screenshots` tab.
- Verify the screenshot overlay darkens the screen slightly, shows a live selection rectangle, and completes capture on mouse release.
- Verify the screenshot overlay shows a lightweight hint and a live size readout while you drag.
- Verify the screenshot timestamp matches the moment the selection is completed.
- Verify each screenshot automatically creates a linked timeline marker at the same timestamp.
- Verify the transcript timeline reflects the screenshot marker event without creating redundant duplicate rows.
- Verify the recording controls window shows only `Start Recording`, `Stop Recording`, `Capture Screenshot`, and `Close`.
- With several screenshots in one session, open the `Screenshots` tab and verify previews load promptly without obvious UI hitching or full-size-image jank.
- Verify the screenshot shows its linked marker label or timeline label when practical.
- Click a screenshot thumbnail in the `Screenshots` tab and verify BugNarrator opens the saved image cleanly.
- Click `Show in Transcript` from a screenshot entry and verify the review workspace switches back to the transcript timeline.
- Open a captured screenshot from the review window and verify Finder reveals the file.
- Export a session bundle and verify `transcript.txt`, `transcript.md`, `summary.md`, and the `screenshots` folder are present.
- Export a session bundle and verify `recent-log.txt` is present and readable.
- Verify the exported `transcript.txt` contains the raw session transcript and the exported `screenshots` folder copies only screenshots that still exist on disk.
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

- Complete a full start-record-stop-transcribe cycle with multiple screenshots.
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
- Force or simulate a restricted microphone state if practical.
  Expected: recording does not start and BugNarrator explains that microphone access is restricted rather than simply denied.
- Use a local unsigned Xcode / DerivedData build after switching app copies or paths.
  Expected: BugNarrator explains that local builds can need microphone approval again because macOS tracks permission by app bundle path.
- Keep microphone access enabled in System Settings for the same BugNarrator app copy, then retry recording after a stale blocked state.
  Expected: BugNarrator rechecks microphone availability with a live recorder probe and starts recording instead of repeating a false denied error.
- Simulate microphone capture setup failing after permission is already granted if practical.
  Expected: BugNarrator reports a microphone availability problem instead of claiming recording started and then immediately failing.
- Capture a screenshot without Screen Recording permission.
  Expected: recording continues, BugNarrator shows a screenshot-specific error, and `Open Screen Recording Settings` opens the expected privacy pane or a safe fallback.
- Start a screenshot selection and release without dragging a real region.
  Expected: BugNarrator treats the attempt as a cancelled screenshot instead of saving a tiny or empty image.
- Start a screenshot selection and press `Esc`.
  Expected: selection mode exits cleanly, recording continues, and BugNarrator shows only a lightweight cancellation message.
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
- Run `xcodebuild test` while another normal BugNarrator copy is already running.
  Expected: the test run still boots cleanly instead of failing because single-instance enforcement terminated the XCTest host.

## Persistence And Cleanup

- Create several sessions, quit the app, relaunch, and verify the session library reloads correctly.
- If you can simulate a corrupted session-history file, verify the app still recovers from the backup copy instead of showing an empty library.
- Delete a session with screenshots and verify the managed screenshot folder is removed.
- Confirm deleting one session does not remove unrelated files or folders outside BugNarrator's managed session-assets directory.

## Settings Regression

- Change auto-copy, auto-save, and auto-extract toggles and verify the next session follows the new values.
- On a fresh settings domain, verify the start, stop, and screenshot hotkeys all show `Not Set`.
- Change the start, stop, and screenshot hotkeys and verify the new shortcuts are registered.
- Clear an assigned shortcut and verify it returns to `Not Set` and no longer triggers globally.
- Assign the same shortcut to two different actions and verify BugNarrator rejects the conflicting assignment with a clear message instead of silently reassigning another action.
- While recording, verify secret fields are disabled.
- Enable Debug Mode and confirm temporary audio files are retained after a completed or cancelled session.
- Disable Debug Mode and confirm temporary audio files are cleaned up after a completed or cancelled session.
- Enable Debug Mode and verify recent diagnostics logs become more verbose than they are in the default mode.
