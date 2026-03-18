# Windows Validation Checklist

Use this checklist on a real Windows machine or VM to validate the current BugNarrator Windows milestones.

Source-of-truth documents:

- [Windows Implementation Roadmap](WINDOWS_IMPLEMENTATION_ROADMAP.md)
- [Cross-Platform Guidelines](../../docs/CROSS_PLATFORM_GUIDELINES.md)

## Environment Setup
- Install the .NET 8 SDK.
- Install Visual Studio 2022 with `.NET desktop development` if you want the easiest local run/debug flow.
- Clone the repo and check out the active Windows branch.
- Open the repo root and confirm `windows/` exists.

## Build And Test Commands
Run on Windows:

```powershell
dotnet restore windows/BugNarrator.Windows.sln
dotnet build windows/BugNarrator.Windows.sln -c Debug
dotnet test windows/BugNarrator.Windows.sln -c Debug
```

Scripted equivalents:

```powershell
powershell -ExecutionPolicy Bypass -File windows/scripts/build-windows.ps1 -Configuration Debug
powershell -ExecutionPolicy Bypass -File windows/scripts/test-windows.ps1 -Configuration Debug
powershell -ExecutionPolicy Bypass -File windows/scripts/package-windows.ps1 -Configuration Release
```

Optional run command:

```powershell
dotnet run --project windows/src/BugNarrator.Windows/BugNarrator.Windows.csproj -c Debug
```

## Automated Coverage Notes
- `BugNarrator.Core.Tests` currently covers deterministic screenshot artifact naming, screenshot-linked timeline moment shaping, completed-session markdown output, session-library query behavior across `Yesterday`, `Last 30 Days`, and `Custom Date Range`, and structured issue-extraction parsing.
- `BugNarrator.Windows.Tests` currently covers screenshot lifecycle orchestration, Milestone 5 stop-recording orchestration, OpenAI issue extraction behavior, GitHub/Jira export provider behavior, session bundle export, debug bundle export, Milestone 6 review-action orchestration, completed-session deletion, corrupted secret handling, session-path hardening, debug-log redaction, Windows hotkey validation, hotkey settings persistence, hotkey registration status, and hotkey-to-recording action routing.
- Current passing automated coverage on this branch is `9` core tests and `27` Windows tests.
- Manual validation is still required for overlay rendering, region selection behavior, desktop capture fidelity, live OpenAI transcription, live OpenAI issue extraction, real GitHub/Jira credentials, DPI scaling, multi-monitor behavior, reserved Windows shortcuts, alternate keyboard layouts, and out-of-focus hotkey behavior against real desktop apps.

## Milestone 2: Tray Shell And Single Instance
- Launch BugNarrator.
- Confirm a tray icon appears.
- Confirm the tray menu includes:
  - `Show Recording Controls`
  - `Open Session Library`
  - `Settings`
  - `About`
  - `Quit`
- Confirm the tray icon appears only once.
- Launch the app a second time.
- Confirm a second tray icon does not appear.
- Confirm the original instance remains the active app shell.
- Confirm `Quit` exits the app cleanly.

## Milestone 3: Recording Lifecycle
- Open `Show Recording Controls`.
- Confirm the controls window opens cleanly.
- Click `Start Recording`.
- Confirm microphone preflight runs.
- If the microphone is unavailable or blocked, confirm the failure is clear and does not create a fake recording state.
- If a microphone is available, confirm recording enters the `recording` state.
- Click `Start Recording` again.
- Confirm duplicate recording does not start.
- Click `Stop Recording`.
- Confirm stop completes cleanly.
- Click `Stop Recording` again.
- Confirm duplicate stop does not break the app.

## Milestone 4: Screenshot Capture
- Start a recording.
- Click `Capture Screenshot`.
- Confirm the overlay appears.
- Drag to select a region.
- Confirm only the selected region is captured.
- Start another screenshot capture and press `Esc`.
- Confirm cancellation is clean and recording remains active.
- Trigger screenshot capture with no active recording.
- Confirm the failure is clear and non-crashing.
- Confirm screenshot capture does not stop the recording session.

## Milestone 5: Transcription, Review, And Session Library
- Open `Settings`.
- Confirm the window loads the transcription model, language hint, prompt, and saved OpenAI API key state.
- Save a valid OpenAI API key and confirm the status message reflects the save.
- Click `Validate Key` and confirm the app reports success or a clear failure.
- Start and stop a recording with an API key configured.
- Confirm the status passes through a saving/transcribing step and then opens the session library.
- Confirm the newest session appears in the library and can be selected.
- Use the search box, date filter, and sort order controls.
- Confirm the selected session updates the right-hand review workspace.
- Confirm the `Transcript`, `Screenshots`, `Extracted Issues`, and `Summary` tabs all switch correctly.
- For a session with screenshots, confirm the screenshot list and preview both load.
- Switch between `Today`, `Yesterday`, `Last 7 Days`, `Last 30 Days`, and `All Sessions`.
- Confirm the expected saved sessions appear in each filter bucket.
- Choose `Custom Date Range`, adjust both dates, and confirm the list updates as the date range changes.
- Repeat stop-recording with no API key configured.
- Confirm the session is still saved and the transcript tab shows a clear fallback message instead of crashing.
- If possible, force a transcription failure with an invalid key or blocked network.
- Confirm the failed session is still saved and the summary/transcript views explain what happened.

## Post-MVP Session Library Parity
- Select an older completed session.
- Click `Delete Session`.
- Confirm the confirmation dialog explains that local session artifacts will be removed.
- Cancel once and confirm the session is still present.
- Repeat the delete flow and confirm the session disappears from the library.
- If other sessions remain, confirm the selection moves cleanly to another saved session.
- If no sessions remain in the active filter, confirm the empty-state text explains the current filter or search state.

## Post-MVP Parity: Windows Global Hotkeys
- Open `Settings`.
- On a fresh settings state, confirm `Start Recording`, `Stop Recording`, and `Capture Screenshot` all show `Not Set`.
- Assign a unique shortcut to each action and click `Save`.
- Confirm each action reports an active global shortcut status after save.
- Switch focus to another desktop app and trigger the configured `Start Recording` hotkey.
- Confirm BugNarrator starts recording without needing the controls window to have focus.
- Trigger the configured `Capture Screenshot` hotkey while recording is active.
- Confirm screenshot capture enters the existing screenshot-selection flow without breaking recording.
- Trigger the configured `Stop Recording` hotkey from another app.
- Confirm the session stops cleanly and the session library opens as expected.
- Clear one assigned shortcut, click `Save`, and confirm it returns to `Not Set` and no longer triggers globally.
- Attempt to assign the same shortcut to two actions.
- Confirm the duplicate assignment is rejected with a clear error before save completes.
- Attempt to capture an invalid shortcut such as a modifier-only input.
- Confirm the settings flow rejects it with a clear message.
- If possible, choose a shortcut already reserved by another app or Windows and click `Save`.
- Confirm the shortcut remains saved but the status explains that Windows could not register it.
- Relaunch BugNarrator and confirm previously assigned shortcuts re-register or surface the same unavailable warning.

## Post-MVP Hardening
- Corrupt or replace a local screenshot file for a completed session.
- Open the session library and select that session.
- Confirm the preview pane shows a safe fallback message instead of crashing the app.
- If you can, temporarily break local internet access and run:
  - `Validate Key`
  - `Extract Issues`
  - `Export To GitHub (Experimental)` or `Export To Jira (Experimental)` with configured credentials
- Confirm each action fails with a clear connectivity or timeout message rather than an unhandled exception.
- If you can, tamper with a saved `session.json` screenshot path so it points outside the session directory.
- Confirm the session library still loads and session bundle export does not pull unrelated local files into the export.
- If you can, corrupt a file under `%LocalAppData%\BugNarrator\Secrets\`.
- Confirm Settings still opens and behaves as if the damaged secret is missing instead of crashing the whole window.

## Milestone 6: Issue Extraction, Exports, And Diagnostics
- Open `Settings`.
- Confirm the issue extraction model, GitHub settings, and Jira settings all load and save.
- Save an OpenAI API key, GitHub token, and Jira credentials if you have real test credentials available.
- Open a completed session with transcript text.
- Click `Extract Issues`.
- Confirm the app reports progress and then renders editable draft issues in the `Extracted Issues` tab.
- Edit at least one draft issue title, summary, category, note, or export-selection checkbox.
- Click `Save Review`.
- Confirm the status message reports that the review edits were saved.
- Click `Export Session Bundle`.
- Confirm the app reports a bundle path under `%LocalAppData%\BugNarrator\Exports\SessionBundles\`.
- Click `Export Debug Bundle`.
- Confirm the app reports a bundle path under `%LocalAppData%\BugNarrator\Exports\DebugBundles\`.
- If real GitHub credentials are configured, click `Export To GitHub (Experimental)`.
- Confirm the selected issues export and the status message reports the first remote URL.
- If real Jira credentials are configured, click `Export To Jira (Experimental)`.
- Confirm the selected issues export and the status message reports the first remote URL.
- Run `powershell -ExecutionPolicy Bypass -File windows/scripts/package-windows.ps1 -Configuration Release`.
- Confirm `windows/artifacts/packages/BugNarrator-windows-win-x64.zip` is created.

## Artifact Validation
Inspect:

- `%LocalAppData%\BugNarrator\Sessions\`
- `%LocalAppData%\BugNarrator\Logs\windows-shell.log`
- `%LocalAppData%\BugNarrator\Exports\SessionBundles\`
- `%LocalAppData%\BugNarrator\Exports\DebugBundles\`

For a successful recording session, confirm:
- a timestamped draft session folder exists
- `session.wav` exists
- `session-draft.json` exists
- `session.json` exists after stop completes
- `transcript.md` exists after stop completes

For a successful screenshot capture, confirm:
- `screenshots\` exists inside the active session
- screenshot files are named deterministically, such as `screenshot-001.png`
- screenshot files are non-empty
- `session-draft.json` includes screenshot metadata
- `session-draft.json` includes the screenshot-linked timeline moment

For Milestone 5 completion paths, confirm:
- `session.json` includes transcription status, model, transcript text or fallback status, screenshot metadata, and timeline moments
- `transcript.md` contains the review summary and transcript or a clear fallback note
- sessions created without an API key still write `session.json` and `transcript.md`
- sessions with transcription failure still write `session.json` and `transcript.md`
- custom date range filtering behaves inclusively for both start and end dates
- deleting a session removes its folder from `%LocalAppData%\BugNarrator\Sessions\`

For Milestone 6 completion paths, confirm:
- `session.json` includes extracted issue metadata when issue extraction completes
- edits to extracted issue title, category, summary, note, and export selection persist after `Save Review`
- exported session bundles contain `transcript.md`
- exported session bundles contain a `screenshots\` directory and copy any existing screenshot files without leaking secrets
- exported debug bundles contain `system-info.json`, `app-version.txt`, `windows-version.txt`, `recent-log.txt`, and `session-metadata.json`
- exported debug bundles do not contain OpenAI, GitHub, or Jira secrets
- the package script outputs `windows/artifacts/packages/BugNarrator-windows-win-x64.zip`

For the hardening milestone, confirm:
- corrupted or tampered session metadata does not cause the app to leave the BugNarrator session root when loading screenshots or exporting bundles
- unreadable secret blobs are treated as missing values instead of breaking the Settings window
- recent debug-log output redacts bearer/basic authorization material and common token patterns
- network outages or service timeouts produce user-facing status text that is actionable

For the hotkey parity milestone, confirm:
- `settings.json` persists the configured `Start Recording`, `Stop Recording`, and `Capture Screenshot` shortcuts
- a cleared shortcut returns to `Not Set` and no longer registers globally
- saved shortcuts restore on app relaunch
- an unavailable shortcut reports a clear status without crashing the tray app

## Logging Checks
Confirm the log file includes useful entries for:
- app launch
- tray shell initialized
- duplicate instance detection
- recording start requested
- microphone preflight result
- recording started
- recording stop requested
- recording stopped
- transcription requested, skipped, completed, or failed
- issue extraction requested, succeeded, or failed
- completed review session saved
- screenshot capture requested
- screenshot preflight result
- screenshot selection cancelled when applicable
- screenshot captured or screenshot failure
- hotkey registration success, failure, and duplicate-assignment rejection
- hotkey invocation
- session bundle export
- debug bundle export
- GitHub export and Jira export outcomes
- app exit

## Failure Cases To Probe
- no microphone device available
- microphone access blocked
- duplicate `Start Recording`
- duplicate `Stop Recording`
- screenshot capture with no active session
- screenshot selection cancel via `Esc`
- tiny accidental screenshot drag region
- stop recording with no OpenAI API key configured
- invalid OpenAI API key
- OpenAI network or service failure during transcription
- OpenAI network or service failure during issue extraction
- GitHub token rejected or repository not found
- Jira credentials rejected or issue type invalid
- corrupted `session.json` screenshot paths
- broken screenshot image files
- corrupted protected secret material under `%LocalAppData%\BugNarrator\Secrets\`
- modifier-only or otherwise invalid hotkey input
- duplicate hotkey assignment in Settings
- saved hotkey unavailable because Windows or another app already owns it
- exporting with no extracted issues selected
- second app launch while first is already running

## Pass Criteria
The current Windows milestones are in good shape if:
- the tray shell is stable
- second launch does not create duplicate shell state
- recording starts and stops cleanly
- session draft artifacts are written
- completed review sessions are written and reload in the session library
- screenshot selection works
- screenshot capture does not interrupt recording
- the review workspace shows transcript and screenshot content for saved sessions
- the session library supports the same core date filters as macOS and can delete local sessions cleanly
- optional global hotkeys work when assigned and stay out of the way when left as `Not Set`
- unavailable or conflicting hotkeys fail clearly without destabilizing the tray app or recording workflow
- extracted issues can be edited and re-saved
- bundle and debug export both produce the expected local artifacts
- the app survives damaged local state and redacts sensitive diagnostics in support bundles
- experimental GitHub/Jira export either succeeds or fails with clear user-facing feedback
- missing or failed transcription still saves the session and keeps the app usable
- logs are useful enough to diagnose failures

## Notes To Record During Validation
Capture these details for each failure:
- exact branch or commit
- whether the test was run from Visual Studio or CLI
- Windows version
- whether microphone hardware was available
- whether the screenshot overlay appeared
- whether an OpenAI API key was configured
- exact user-facing error text
- whether logs and session draft artifacts were written
