# Windows Validation Checklist

Use this checklist on a real Windows machine or VM to validate the current BugNarrator Windows milestones.

Source-of-truth documents:

- [Windows Implementation Roadmap](/Users/deffenda/Code/FeedbackMic/windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md)
- [Cross-Platform Guidelines](/Users/deffenda/Code/FeedbackMic/docs/CROSS_PLATFORM_GUIDELINES.md)

## Environment Setup
- Install the .NET 8 SDK.
- Install Visual Studio 2022 with `.NET desktop development` if you want the easiest local run/debug flow.
- Clone the repo and check out the active Windows branch.
- Open the repo root and confirm `windows/` exists.

## Build And Test Commands
Run on Windows:

```powershell
dotnet restore windows/BugNarrator.Windows.sln
dotnet build windows/src/BugNarrator.Windows/BugNarrator.Windows.csproj -c Debug
dotnet test windows/tests/BugNarrator.Core.Tests/BugNarrator.Core.Tests.csproj -c Debug
```

Optional run command:

```powershell
dotnet run --project windows/src/BugNarrator.Windows/BugNarrator.Windows.csproj -c Debug
```

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

## Artifact Validation
Inspect:

- `%LocalAppData%\BugNarrator\Sessions\`
- `%LocalAppData%\BugNarrator\Logs\windows-shell.log`

For a successful recording session, confirm:
- a timestamped draft session folder exists
- `session.wav` exists
- `session-draft.json` exists

For a successful screenshot capture, confirm:
- `screenshots\` exists inside the active session
- screenshot files are named deterministically, such as `screenshot-001.png`
- screenshot files are non-empty
- `session-draft.json` includes screenshot metadata
- `session-draft.json` includes the screenshot-linked timeline moment

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
- screenshot capture requested
- screenshot preflight result
- screenshot selection cancelled when applicable
- screenshot captured or screenshot failure
- app exit

## Failure Cases To Probe
- no microphone device available
- microphone access blocked
- duplicate `Start Recording`
- duplicate `Stop Recording`
- screenshot capture with no active session
- screenshot selection cancel via `Esc`
- tiny accidental screenshot drag region
- second app launch while first is already running

## Pass Criteria
The current Windows milestones are in good shape if:
- the tray shell is stable
- second launch does not create duplicate shell state
- recording starts and stops cleanly
- session draft artifacts are written
- screenshot selection works
- screenshot capture does not interrupt recording
- logs are useful enough to diagnose failures

## Notes To Record During Validation
Capture these details for each failure:
- exact branch or commit
- whether the test was run from Visual Studio or CLI
- Windows version
- whether microphone hardware was available
- whether the screenshot overlay appeared
- exact user-facing error text
- whether logs and session draft artifacts were written
