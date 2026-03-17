# BugNarrator Windows Implementation Roadmap

## Purpose

This document defines the Windows MVP direction for BugNarrator and turns it into an implementation plan that is ready to execute in milestones.

The BugNarrator Spec and the current macOS implementation remain the product source of truth. This document translates that product into a practical Windows-first plan without changing the core direction.

The Windows version should preserve the same durable workflow:

`record -> review -> refine -> export`

## Product Goal

Build a Windows desktop version of BugNarrator that allows a tester to:

- launch BugNarrator from the Windows system tray
- open a small recording controls window
- record microphone audio while continuing to use other apps
- capture selected screenshot regions during a session
- transcribe finished sessions with the user's own OpenAI API key
- review transcript, screenshots, summary, and extracted issues
- export a local session bundle
- optionally export selected issues to GitHub and Jira as experimental integrations

## Non-Goals For MVP

- no backend
- no cloud sync
- no accessibility automation
- no live dictation into other apps
- no system audio capture unless explicitly added later
- no attempt to share the macOS UI layer directly

## Product Principles

- preserve BugNarrator as a serious local developer/testing tool
- keep the workflow simple and durable
- favor reliability over feature expansion
- keep exported artifacts local and understandable
- use platform-native Windows behavior where practical
- treat GitHub and Jira export as experimental

## Recommended Tech Stack

- Language/runtime: C# / .NET 8
- Desktop UI: WPF
- MVVM helpers: CommunityToolkit.Mvvm
- Tray integration: WPF plus a tray icon host
- Audio recording: NAudio or Media Foundation
- Region screenshot capture: Windows Graphics Capture plus a custom region-selection overlay
- Secret storage: Windows Credential Manager or DPAPI
- Local storage: JSON and files under `%AppData%` or `%LocalAppData%`
- Logging: `Microsoft.Extensions.Logging` plus local rolling log files
- Packaging: signed installer `.exe` first, MSIX later if needed

WPF is the recommended MVP choice because tray apps, overlay windows, hotkeys, and desktop window control are mature and predictable there.

## Core Product And Architecture Shape

Split the Windows version into:

- `BugNarrator.Core`
- `BugNarrator.Windows`
- `BugNarrator.Windows.Services`

### BugNarrator.Core

Owns platform-neutral app logic:

- session models
- transcript session model
- recording draft model
- screenshot metadata model
- extracted issue model
- issue extraction response parsing
- session library filtering, search, and sort rules
- transcript/timeline shaping
- export payload shaping
- session bundle export rules
- debug bundle export rules
- app state and error models

### BugNarrator.Windows

Owns Windows UI:

- app entry point
- tray lifecycle
- recording controls window
- session library window
- settings window
- about/changelog/support windows
- review workspace
- view models and commands

### BugNarrator.Windows.Services

Owns Windows integrations:

- microphone permission and capture preflight
- screen capture permission and screenshot preflight
- audio recorder service
- region-selection overlay service
- screenshot capture service
- global hotkey registration
- secure secret storage
- file/path location service
- clipboard service
- URL opening service
- single-instance enforcement
- diagnostics logging

## Core User Experience

### Launch

- BugNarrator launches as a system tray app
- only one instance is allowed
- launching a second copy should focus the existing instance and exit the new one

### Recording Controls

The tray menu should expose a prominent action equivalent to:

- `Show Recording Controls`

The recording controls window should include:

- `Start Recording`
- `Stop Recording`
- `Capture Screenshot`
- `Close`

The controls window should remain open until the user closes it.

### Recording

- recording runs in the background while the tester uses other apps
- recording must not start twice
- recording must stop cleanly
- screenshot capture must not interrupt audio recording

### Screenshot Capture

- screenshot capture should use a drag-select region overlay
- the overlay should feel lightweight and native to Windows
- each screenshot should attach to the active session
- each screenshot should create a timeline moment at the same timestamp

### Review Workspace

The session library should remain the main review surface.

Recommended right-hand tabs:

- `Transcript`
- `Screenshots`
- `Extracted Issues`
- `Summary`

The `Screenshots` tab should act as both:

- screenshot evidence list
- important-moments index

### Export

Session bundle export should match current product behavior:

- `transcript.md`
- `screenshots/`

GitHub and Jira export should remain explicitly experimental.

## Main Runtime Flows

### App Launch Flow

1. enforce single instance
2. initialize diagnostics
3. load settings and secrets
4. load session library metadata
5. show tray icon

### Start Recording Flow

1. open/focus recording controls
2. run microphone preflight
3. if blocked, show clear recovery guidance
4. if allowed, start microphone capture
5. create session draft and begin elapsed-time tracking

### Capture Screenshot Flow

1. run screenshot permission/capability preflight
2. if blocked, show screenshot-specific guidance
3. show region-selection overlay
4. capture selected region
5. save screenshot file
6. attach screenshot metadata to current session
7. create timeline moment at the same timestamp
8. keep recording active even if screenshot capture fails

### Stop Recording Flow

1. stop capture cleanly
2. persist draft artifacts
3. send audio to OpenAI transcription
4. build transcript and session metadata
5. save completed session locally
6. focus the session library

### Issue Extraction Flow

1. user requests issue extraction from the selected session
2. send transcript context to OpenAI
3. parse extraction output into structured draft issues
4. keep results editable before export
5. if no issues are found, keep the workspace in a valid fallback state

## Recommended Development Approach

Do not attempt a one-shot port of the macOS app.

Instead:

1. preserve the BugNarrator workflow and product language
2. split platform-neutral logic from Windows-specific UI and OS integrations
3. de-risk the hardest Windows behaviors early
4. implement in milestones that each leave the app in a working state

## High-Level Roadmap

### Milestone 1: Solution Scaffold

Goal:

- create the Windows solution and project structure
- establish the architectural split
- get the app building cleanly on Windows

Deliverables:

- `windows/src/BugNarrator.Core/`
- `windows/src/BugNarrator.Windows/`
- `windows/src/BugNarrator.Windows.Services/`
- `windows/tests/BugNarrator.Core.Tests/`
- `windows/tests/BugNarrator.Windows.Tests/`
- `windows/scripts/`
- `windows/BugNarrator.Windows.sln`

Outcomes:

- .NET 8 solution builds
- WPF shell launches
- test project runs
- logging/config/path plumbing exists

### Milestone 2: Tray App And Single Instance

Goal:

- turn the app into a usable Windows tray app shell

Deliverables:

- tray icon
- tray menu
- single-instance enforcement
- focus-existing-instance behavior
- startup and shutdown logging

Outcomes:

- one tray icon only
- second launch reuses the first instance
- app has a stable shell before feature work continues

### Milestone 3: Recording Controls And Mic Recording

Goal:

- implement a working recording flow

Deliverables:

- recording controls window
- microphone preflight
- start/stop recording
- background audio capture
- local session draft persistence

Outcomes:

- recording cannot overlap
- start/stop behavior is deterministic
- audio artifacts are created locally

### Milestone 4: Screenshot Region Capture

Goal:

- add screenshot capture without destabilizing recording

Deliverables:

- screenshot preflight
- drag-select overlay
- screenshot file save flow
- screenshot metadata
- screenshot timeline moment creation

Outcomes:

- screenshot capture works during an active session
- cancelled screenshots do not break recording
- the saved artifact model matches the current product direction

### Milestone 5: Transcription, Review, And Session Library

Goal:

- make recorded sessions reviewable end to end

Deliverables:

- OpenAI key settings and secure storage
- transcription client
- completed session persistence
- session library browsing
- review workspace

Outcomes:

- sessions can be recorded, transcribed, saved, reopened, and reviewed
- transcript and screenshots are visible in the Windows app

### Milestone 6: Issue Extraction, Exports, And Diagnostics

Goal:

- reach Windows MVP feature completeness

Deliverables:

- issue extraction
- editable/selectable draft issues
- session bundle export
- debug bundle export
- experimental GitHub export
- experimental Jira export
- structured local diagnostics

Outcomes:

- Windows MVP supports the full review and export loop
- supportability and artifact export are in place

### Milestone 7: Packaging, Signing, And Release Readiness

Goal:

- make the Windows app distributable to external testers

Deliverables:

- installer packaging
- signing scripts and docs
- release checklist
- clean-machine validation

Outcomes:

- signed public test build
- repeatable Windows release process

## Suggested Repo Skeleton

```text
windows/
  docs/
    WINDOWS_MVP_SPEC.md
    WINDOWS_IMPLEMENTATION_ROADMAP.md
    WINDOWS_SIGNING_AND_RELEASE.md
  src/
    BugNarrator.Core/
      Models/
      Workflow/
      SessionLibrary/
      Export/
      Extraction/
      Diagnostics/
    BugNarrator.Windows/
      App.xaml
      App.xaml.cs
      Tray/
      Views/
      ViewModels/
      Commands/
      Themes/
      Assets/
    BugNarrator.Windows.Services/
      Audio/
      Capture/
      Permissions/
      Hotkeys/
      Storage/
      Secrets/
      Shell/
      Diagnostics/
  tests/
    BugNarrator.Core.Tests/
    BugNarrator.Windows.Tests/
  scripts/
    build-windows.ps1
    test-windows.ps1
    package-windows.ps1
    sign-windows.ps1
  BugNarrator.Windows.sln
```

## Recommended Ownership By Project

### BugNarrator.Core

Own:

- models
- transcript/review data shaping
- issue extraction parsing
- export payload shaping
- session-library filtering/search/sort
- app state contracts
- error models

Avoid:

- direct Windows API usage
- WPF types
- file-system location assumptions tied to Windows shell behavior

### BugNarrator.Windows

Own:

- WPF windows
- tray shell
- window/viewmodel composition
- user commands and interaction flow

Avoid:

- deep business logic
- direct secret handling where an abstraction can be used

### BugNarrator.Windows.Services

Own:

- microphone capture
- screenshot capture
- permissions
- secure storage
- hotkeys
- clipboard
- URL opening
- shell integration
- diagnostics plumbing

## Recommended Milestone Order

1. scaffold the solution
2. make the tray app work
3. make recording work
4. make screenshots work
5. make transcription and review work
6. make extraction/export/diagnostics work
7. make packaging and signing work

This order keeps the highest-risk OS behavior early and postpones lower-risk integrations until the Windows shell is stable.

## Windows-Specific Replacements

Replace current macOS-specific pieces with Windows-native equivalents:

- menu bar app -> system tray app
- AppKit/SwiftUI windows -> WPF windows
- AVFoundation microphone capture -> NAudio or Media Foundation
- ScreenCaptureKit -> Windows Graphics Capture plus custom overlay
- Keychain -> Credential Manager or DPAPI
- Carbon/macOS hotkeys -> Windows global hotkeys
- DMG/notarization flow -> signed Windows installer flow

## Storage Model

Recommended storage root:

- `%AppData%\\BugNarrator\\`
or
- `%LocalAppData%\\BugNarrator\\`

Recommended subfolders:

- `Sessions/`
- `SessionAssets/`
- `Logs/`
- `Cache/`

Suggested per-session structure:

- `session.json`
- `transcript.md`
- `screenshots/`

The storage format should stay deterministic, local, and human-inspectable.

## Security And Privacy

- keep all session artifacts local unless the user explicitly invokes OpenAI or export workflows
- store secrets in Windows-secure storage, not plain preferences
- avoid leaking tokens or transcript content into logs unless explicitly allowed
- keep debug bundle output scrubbed of raw credentials

## Diagnostics

The Windows MVP should include structured local diagnostics for:

- launch and shutdown
- permission checks
- recording lifecycle
- screenshot capture
- transcription and issue extraction
- export workflows

Diagnostics should be exportable in a debug bundle for support.

## Packaging And Signing

Initial Windows release path:

- build release app
- package signed installer
- sign `BugNarrator.exe`
- sign installer
- timestamp both
- verify signatures
- publish stable and versioned installer assets to GitHub Releases

MSIX can be evaluated later, but it is not required for MVP.

## Risk Areas To Spike Early

Before deep implementation, validate these with small prototypes:

- tray icon lifecycle in WPF
- single-instance focus behavior
- microphone capture reliability
- drag-select screenshot overlay on multi-monitor setups
- global hotkey registration conflicts
- secure secret storage behavior

If any of these are shaky, adjust architecture before the main build-out.

## Milestone-by-Milestone Build Prompts

These prompts are intended for iterative implementation, not one-shot generation.

### Prompt 1: Solution Scaffold

```md
Use the BugNarrator Spec, the current macOS repo, and `windows/docs/WINDOWS_MVP_SPEC.md` as the source of truth.

Execute Milestone 1 for the Windows version of BugNarrator.

Objective:
Set up the Windows solution skeleton only. Do not implement full product behavior yet.

Deliverables:
1. create `windows/` solution structure
2. create projects:
   - `BugNarrator.Core`
   - `BugNarrator.Windows`
   - `BugNarrator.Windows.Services`
   - `BugNarrator.Core.Tests`
3. choose WPF + .NET 8
4. wire project references cleanly
5. add basic logging/config/path infrastructure
6. add a minimal app shell that can launch successfully
7. add a minimal tray/app entry structure placeholder
8. document how to build the Windows solution

Constraints:
- do not add full recording yet
- do not add screenshot capture yet
- keep architecture clean and future-proof
- prefer small, testable files

Validation:
- solution restores
- solution builds
- basic test project runs

Return:
- files created
- architecture decisions made
- build commands
- next recommended milestone
```

### Prompt 2: Tray App And Single Instance

```md
Use the BugNarrator Spec, the current macOS repo, and `windows/docs/WINDOWS_MVP_SPEC.md` as the source of truth.

Execute Milestone 2 for the Windows version of BugNarrator.

Objective:
Implement the Windows tray shell and single-instance behavior.

Deliverables:
1. add a tray icon
2. add a tray menu with:
   - Show Recording Controls
   - Open Session Library
   - Settings
   - About
   - Quit
3. enforce single-instance behavior
4. if a second instance launches, focus the existing app and exit the new one
5. add safe startup/shutdown logging
6. add basic Windows shell integration services

Constraints:
- do not add full recording yet
- keep behavior close to the macOS product model
- no duplicate tray icons
- keep the tray menu simple and professional

Validation:
- app launches from Windows normally
- tray icon appears once
- second launch does not create a duplicate instance

Return:
- files changed
- single-instance approach used
- remaining tray-shell risks
```

### Prompt 3: Recording Controls And Mic Recording

```md
Use the BugNarrator Spec, the current macOS repo, and `windows/docs/WINDOWS_MVP_SPEC.md` as the source of truth.

Execute Milestone 3 for the Windows version of BugNarrator.

Objective:
Implement the recording controls window, microphone preflight, and stable start/stop recording.

Deliverables:
1. create the recording controls window
2. include:
   - Start Recording
   - Stop Recording
   - Capture Screenshot
   - Close
3. add microphone preflight and capability checks
4. block recording cleanly when mic access/capture is unavailable
5. record audio in the background
6. persist a local session draft
7. keep state transitions deterministic:
   - idle
   - recording
   - stopping
   - failed
   - completed

Constraints:
- do not implement transcription yet
- no overlapping sessions
- no fake recording state on failure
- keep UI minimal

Validation:
- start/stop works
- duplicate start is blocked
- duplicate stop is safe
- recording file is created locally

Return:
- files changed
- mic stack used
- known Windows audio risks
```

### Prompt 4: Screenshot Region Capture

```md
Use the BugNarrator Spec, the current macOS repo, and `windows/docs/WINDOWS_MVP_SPEC.md` as the source of truth.

Execute Milestone 4 for the Windows version of BugNarrator.

Objective:
Implement drag-select screenshot capture during an active session.

Deliverables:
1. add screenshot preflight
2. build a lightweight region-selection overlay
3. support:
   - click and drag
   - live rectangle preview
   - Esc to cancel
   - mouse release to capture
4. save the screenshot into the active session
5. create a timeline moment at the same timestamp
6. keep recording active if screenshot capture fails
7. add basic review-side screenshot metadata support

Constraints:
- do not interrupt audio recording
- do not capture full desktop by default
- keep the overlay simple and native-feeling

Validation:
- screenshot file is created
- metadata is saved
- cancellation works
- recording remains stable during capture

Return:
- files changed
- capture API choice
- multi-monitor risks
```

### Prompt 5: Transcription, Session Library, Review Workspace

```md
Use the BugNarrator Spec, the current macOS repo, and `windows/docs/WINDOWS_MVP_SPEC.md` as the source of truth.

Execute Milestone 5 for the Windows version of BugNarrator.

Objective:
Implement transcription, local session persistence, session library browsing, and the review workspace.

Deliverables:
1. add secure OpenAI API key storage
2. implement transcription client
3. save completed sessions locally
4. build a session library with:
   - list
   - search
   - sort
   - selection
5. build a right-hand review workspace with tabs:
   - Transcript
   - Screenshots
   - Extracted Issues
   - Summary
6. preserve the current BugNarrator workflow and wording where practical

Constraints:
- do not over-design the UI
- keep the review pane readable at smaller widths
- no backend

Validation:
- stop recording triggers transcription
- completed sessions appear in the library
- review tabs switch correctly
- app survives transcription failures cleanly

Return:
- files changed
- storage model used
- remaining review-workspace gaps
```

### Prompt 6: Extraction, Exports, Diagnostics, Packaging

```md
Use the BugNarrator Spec, the current macOS repo, and `windows/docs/WINDOWS_MVP_SPEC.md` as the source of truth.

Execute Milestone 6 for the Windows version of BugNarrator.

Objective:
Finish the Windows MVP with issue extraction, exports, diagnostics, and release packaging.

Deliverables:
1. implement issue extraction
2. make extracted issues editable/selectable
3. implement `Export Session Bundle` with:
   - `transcript.md`
   - `screenshots/`
4. implement debug bundle export
5. keep GitHub and Jira export marked experimental
6. add structured diagnostics logging
7. add Windows packaging scripts
8. document signing and release steps

Constraints:
- do not add non-MVP features
- no secret leakage in logs or debug bundles
- keep GitHub/Jira export clearly experimental

Validation:
- issue extraction works
- session bundle export works
- debug bundle excludes secrets
- installer/package build flow succeeds

Return:
- files changed
- packaging format chosen
- signing/release blockers
- exact next steps for public tester distribution
```

## Recommended Immediate Next Steps

1. accept this roadmap and the MVP spec
2. create the Windows solution skeleton
3. validate the tray app and single-instance spike on a real Windows machine or VM
4. only then begin feature implementation

## MVP Acceptance Criteria

A Windows tester should be able to:

1. install BugNarrator from a signed Windows installer
2. launch the app from the system tray
3. configure an OpenAI API key
4. start recording
5. capture a selected screenshot region during recording
6. stop recording
7. receive transcript and screenshot artifacts
8. review transcript, screenshots, summary, and extracted issues
9. export a session bundle with `transcript.md` and `screenshots/`
10. relaunch the app without duplicate instances or broken session state
