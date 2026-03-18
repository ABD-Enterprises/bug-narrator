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
- browse saved sessions with flexible date filters and delete local sessions when they are no longer needed
- export a local session bundle
- optionally export selected issues to GitHub and Jira as experimental integrations
- survive corrupted local metadata, unreadable secret files, broken screenshot previews, and transient network failures without collapsing the Windows shell

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

Current implementation findings:

- the active Windows branch includes screenshot preflight, drag-select overlay capture, deterministic screenshot file planning, screenshot metadata persistence, and screenshot-linked timeline moment creation
- the WPF shell required explicit global usings in `BugNarrator.Windows` so WinForms tray support does not reintroduce ambiguous type imports and break the Windows build
- automated coverage now includes screenshot planner tests plus Windows screenshot lifecycle tests for no-active-session, preflight failure, cancellation, success, and capture-failure paths
- manual validation is still required on a real Windows desktop for overlay behavior, capture fidelity, DPI scaling, and multi-monitor edge cases
- review-side screenshot display remains Milestone 5 work; Phase 4 only carries the metadata and artifact plumbing needed for that later UI

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

Current implementation findings:

- the active Windows branch now stores transcription settings in `settings.json` under `%LocalAppData%\BugNarrator` and encrypts the OpenAI API key per Windows user with DPAPI-backed local secret storage
- stopping a recording now saves the draft, optionally sends audio to OpenAI transcription, then persists a completed `session.json` plus `transcript.md` in the same session folder before focusing the session library
- the stop-recording flow survives both missing-key and transcription-failure paths by saving a completed review session with a clear fallback status instead of crashing or discarding the recording
- the WPF session library now supports list browsing, search, newest/oldest sorting, Today/Yesterday/Last 7 Days/Last 30 Days/All Sessions/Custom Date Range filtering, transcript review, screenshot preview, a summary tab, and an extracted-issues tab that is ready for editable/selectable Milestone 6 draft issues
- the current Windows branch now supports permanent local session deletion from the session library, including deleting the session folder and its locally stored screenshots after confirmation
- automated coverage now includes core tests for session-library query logic and transcript markdown shaping plus Windows tests for completed-session persistence across success, missing-key, and transcription-failure paths
- manual validation is still required on a real Windows desktop for live OpenAI requests, long recordings, screenshot preview fidelity across DPI and multi-monitor setups, and review-window ergonomics
- OpenAI-generated summaries remain out of scope for the current Windows MVP and are not implemented on this branch

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

Current implementation findings:

- the active Windows branch now includes a Windows issue extraction client that sends completed session transcript context to OpenAI chat completions, requests structured JSON output, and parses that response into `IssueExtractionResult` plus `ExtractedIssue` records in `BugNarrator.Core`
- completed sessions now persist extracted issue results, searchable issue text, and extracted-issue markdown output through the same `session.json` plus `transcript.md` storage model used by earlier milestones
- the WPF session library now allows draft issues to be edited and selected before export, then saves those edits back into the completed session metadata
- local `Export Session Bundle` now writes `transcript.md` plus a copied `screenshots/` directory under `%LocalAppData%\BugNarrator\Exports\SessionBundles\`
- local `Export Debug Bundle` now writes `system-info.json`, `app-version.txt`, `windows-version.txt`, `recent-log.txt`, and `session-metadata.json` under `%LocalAppData%\BugNarrator\Exports\DebugBundles\`
- GitHub export is implemented as an explicitly experimental direct API integration that creates repository issues from the selected draft issues using locally stored owner, repository, labels, and token settings
- Jira export is implemented as an explicitly experimental direct API integration that creates Jira issues from the selected draft issues using locally stored base URL, email, API token, project key, and issue type settings
- DPAPI-backed secret storage now covers OpenAI, GitHub, and Jira credentials for the current Windows user without storing raw secrets in `settings.json`
- packaging/release scaffolding now exists via `windows/scripts/build-windows.ps1`, `windows/scripts/test-windows.ps1`, `windows/scripts/package-windows.ps1`, `windows/scripts/sign-windows.ps1`, and `windows/docs/WINDOWS_SIGNING_AND_RELEASE.md`
- automated coverage now includes `9` core tests and `18` Windows tests, including structured issue parsing, OpenAI extraction client behavior, GitHub/Jira export request behavior, session bundle export, debug bundle export, review-action orchestration, and session-library parity coverage
- validation completed on this branch includes:
  - `powershell -ExecutionPolicy Bypass -File windows/scripts/build-windows.ps1 -Configuration Debug`
  - `powershell -ExecutionPolicy Bypass -File windows/scripts/test-windows.ps1 -Configuration Debug`
  - `powershell -ExecutionPolicy Bypass -File windows/scripts/package-windows.ps1 -Configuration Release`
  - a smoke launch of `windows/artifacts/publish/win-x64/BugNarrator.Windows.exe`
- manual validation is still required on a real Windows desktop for live OpenAI issue extraction, real GitHub/Jira credentials, overlay behavior under mixed DPI and multi-monitor layouts, and overall review-workspace ergonomics

### Post-MVP Hardening Milestone: Reliability, Defensive Coding, And Security

Goal:

- reduce the chance that everyday Windows testing fails because of corrupted local state, unsafe artifact paths, secret-store damage, noisy diagnostics, or brittle network error handling

Deliverables:

- shared atomic file-write helpers for settings, draft metadata, completed-session metadata, transcripts, and local secret material
- shared storage path guards for keeping session and export artifacts inside the expected BugNarrator roots
- completed-session artifact normalization so tampered `session.json` files cannot redirect screenshot or artifact paths outside the local session directory
- diagnostic redaction for common bearer/basic tokens and known OpenAI/GitHub token patterns
- debug bundle redaction and safer session metadata probing
- friendlier network-failure messages for OpenAI, GitHub, and Jira requests
- defensive screenshot preview loading so broken local image files do not crash the session library window

Outcomes:

- the Windows app is more tolerant of corrupted local files and less likely to leak credentials into logs or debug bundles
- the storage and export code is easier to maintain because file safety and redaction rules now live in shared helpers instead of one-off implementations

Current implementation findings:

- atomic writes are now centralized through `AtomicFileOperations`, which reduces duplicated temp-file logic and cleans up temporary files if a write fails mid-flight
- shared path safety helpers now keep local settings, session metadata, and exported artifacts rooted inside the expected BugNarrator storage directories
- completed-session loading now normalizes session-local audio, transcript, metadata, and screenshot paths before the rest of the app consumes them, which means tampered metadata no longer causes bundle export or library review to touch arbitrary local files
- DPAPI secret reads now tolerate corrupt or oversized secret blobs by returning a safe null result instead of breaking settings load for the whole window
- diagnostics and debug bundles now redact common authorization headers and token patterns before writing or exporting log lines
- OpenAI transcription, OpenAI issue extraction, GitHub export, and Jira export now map timeout and connectivity failures to clearer user-facing messages
- screenshot preview loading in the WPF session library now fails closed with a warning message instead of throwing when a local image file is missing or invalid
- automated coverage now includes `9` core tests and `22` Windows tests, with the new Windows coverage focused on corrupted secret handling, safe session-path normalization, debug-log redaction, safer bundle export behavior, and network-failure messaging

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

### Post-MVP Parity Milestone: Session Library Filters And Deletion

Goal:

- close the most visible remaining session-library parity gaps with the macOS app

Deliverables:

- `Yesterday` filter
- `Last 30 Days` filter
- `Custom Date Range` filter
- `Today` default with automatic fallback to `All Sessions` when no same-day sessions exist
- permanent local session deletion from the Windows session library

Outcomes:

- the Windows session library now covers the same core date-filtering model used by the macOS app
- Windows testers can remove stale local review sessions without leaving the app

Current implementation findings:

- the current Windows branch now uses the same session-library date buckets that the macOS app exposes for `Today`, `Yesterday`, `Last 7 Days`, `Last 30 Days`, `All Sessions`, and `Custom Date Range`
- the WPF session library now shows custom start/end date pickers when `Custom Date Range` is selected and automatically switches into that filter when the user edits either date
- the default Windows library view now starts on `Today` and falls back to `All Sessions` when no same-day sessions exist, which matches the current macOS behavior more closely than the earlier always-all default
- session deletion is now routed through the Windows review action service and completed session store so deleting a saved session removes the session directory and its local artifacts from `%LocalAppData%\BugNarrator\Sessions\`
- automated coverage now includes additional core tests for `Yesterday`, `Last 30 Days`, and reversed custom date ranges plus Windows review-action coverage for local completed-session deletion

### Post-MVP Parity Milestone: Windows Global Hotkeys

Goal:

- close the last major macOS workflow-parity gap by making Windows global hotkeys optional, user-assigned, and safe to leave disabled

Deliverables:

- optional `Start Recording`, `Stop Recording`, and `Capture Screenshot` hotkeys
- `Not Set` defaults for all Windows hotkey actions
- Windows-specific hotkey registration built on the standard `RegisterHotKey` API rather than a low-level hook
- assign and clear controls in the Windows Settings window
- duplicate-assignment rejection and invalid-shortcut rejection
- persisted hotkey settings with re-registration on startup and on save
- clear user-facing status for unavailable OS-level shortcuts

Outcomes:

- Windows testers can start, stop, and capture screenshots while another app has focus without reopening the recording controls window
- Windows keeps the recording controls window as the primary live-session surface while making hotkeys truly optional

Current implementation findings:

- the Windows app now uses a hidden Win32 hotkey sink with `RegisterHotKey` and no-repeat registration for `Start Recording`, `Stop Recording`, and `Capture Screenshot`
- all three hotkeys start as `Not Set` and are persisted in `%LocalAppData%\BugNarrator\settings.json`
- the WPF Settings window now supports assign, clear, duplicate rejection, invalid-shortcut rejection, and per-action runtime status for saved global shortcuts
- startup now re-registers saved shortcuts and surfaces a tray warning when one or more saved shortcuts cannot be activated because Windows or another app already owns them
- hotkey invocations route through the existing recording lifecycle service instead of bypassing the current recording and screenshot guards
- automated coverage now includes `9` core tests and `27` Windows tests, with the new Windows coverage focused on hotkey validation, persistence, registration, and action routing
- manual validation is still required on a real Windows desktop for reserved shortcuts, alternate keyboard layouts, mixed-focus behavior, and screenshot hotkeys while the overlay is active

## Current macOS Parity Review

As of March 18, 2026, the current Windows branch is in strong parity with the current macOS app for the core `record -> review -> refine -> export` workflow:

- tray shell, recording controls, optional global hotkeys, microphone recording, screenshot capture, transcription, session review, issue extraction, bundle export, debug bundle export, and experimental GitHub/Jira export are all implemented on Windows
- the post-MVP hardening and hotkey milestones improved the reliability and reach of the existing workflow without reopening already-complete review surfaces
- the remaining work is mostly real-desktop validation and Windows-specific polish around reserved shortcuts, keyboard layouts, DPI, multi-monitor behavior, and third-party integration credentials rather than a missing core workflow phase

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
- package a zipped `dotnet publish` artifact first
- add installer packaging later if tester feedback requires it
- sign `BugNarrator.exe`
- sign the distributable artifact(s)
- timestamp signed outputs
- verify signatures
- publish stable and versioned Windows assets to GitHub Releases

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
Use the current Windows branch plus these repo documents as the source of truth:
- `README.md`
- `docs/UserGuide.md`
- `docs/CROSS_PLATFORM_GUIDELINES.md`
- `windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md`
- `windows/docs/WINDOWS_VALIDATION_CHECKLIST.md`

Execute Phase 4 of the Windows MVP, which maps to Milestone 4: `Screenshot Region Capture`.

Baseline:
- Milestone 3 recording is already in place.
- Phase 4 must add screenshot capture during an active recording session without destabilizing audio capture.
- Full review UI is not part of this phase beyond the screenshot metadata needed for later milestones.

Required outcomes:
1. allow screenshot capture only while an active recording session exists
2. add screenshot preflight with clear user-facing failure states
3. build a lightweight drag-select overlay that supports:
   - click and drag
   - live rectangle preview
   - `Esc` to cancel
   - mouse release to capture
4. capture only the selected region, not the full desktop by default
5. save deterministic screenshot artifacts into the active session, such as `screenshots/screenshot-001.png`
6. persist screenshot metadata and a screenshot-linked timeline moment into `session-draft.json`
7. keep recording active if screenshot capture is cancelled or fails
8. log the screenshot request, preflight result, cancellation, success, and failure paths
9. keep platform-neutral shaping in `BugNarrator.Core` and Windows-specific behavior in the Windows projects

Explicit non-goals:
- transcription
- session library implementation beyond placeholder or metadata shaping
- GitHub or Jira export work
- packaging or signing work
- global hotkey expansion unless it is required to avoid regressions in existing Phase 4 behavior

Validation:
- run:
  - `dotnet restore windows/BugNarrator.Windows.sln`
  - `dotnet build windows/BugNarrator.Windows.sln -c Debug`
  - `dotnet test windows/BugNarrator.Windows.sln -c Debug`
- manually validate the Milestone 4 scenarios in `windows/docs/WINDOWS_VALIDATION_CHECKLIST.md`
- inspect `%LocalAppData%\BugNarrator\Sessions\` and `%LocalAppData%\BugNarrator\Logs\windows-shell.log`
- confirm screenshot capture does not stop or corrupt the active recording session

Documentation updates required:
1. update `windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md` to reflect what Phase 4 actually implemented, any scope changes, and any newly discovered risks or follow-up work
2. update `windows/docs/WINDOWS_VALIDATION_CHECKLIST.md` with any new validation steps, failure cases, or artifact expectations discovered during implementation
3. update `windows/README.md` if the build/run/test instructions or source-of-truth docs changed
4. clearly note anything deferred to Milestone 5 instead of silently leaving it ambiguous

Return:
- files changed
- what was implemented versus deferred
- validation performed and the exact results
- artifact paths produced during validation
- capture API choice
- known risks, especially around overlay behavior, DPI scaling, and multi-monitor setups
- docs updated and why
```

### Prompt 5: Transcription, Session Library, Review Workspace

```md
Use the current Windows branch plus these repo documents as the source of truth:
- `README.md`
- `docs/UserGuide.md`
- `docs/CROSS_PLATFORM_GUIDELINES.md`
- `windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md`
- `windows/docs/WINDOWS_VALIDATION_CHECKLIST.md`

Execute Milestone 5 for the Windows version of BugNarrator.

Objective:
Implement transcription, secure OpenAI settings, completed session persistence, session library browsing, and the review workspace without destabilizing the Milestone 4 recording and screenshot flow.

Deliverables:
1. add secure OpenAI API key storage
2. persist non-secret transcription settings locally
3. implement the OpenAI transcription client
4. save completed sessions locally
5. save `transcript.md` beside completed session metadata
6. build a session library with:
   - list
   - search
   - sort
   - date filtering
   - selection
7. build a right-hand review workspace with tabs:
   - Transcript
   - Screenshots
   - Extracted Issues
   - Summary
8. preserve the current BugNarrator workflow and wording where practical

Behavior requirements:
- stopping a recording should still save the session even when no OpenAI API key is configured
- transcription failures must not discard the recording or leave the app in a broken state
- the session library should auto-focus after a stop completes
- screenshot artifacts created in Milestone 4 must remain visible in the review workspace
- keep platform-neutral session shaping and query logic in `BugNarrator.Core`

Explicit non-goals:
- issue extraction
- AI-generated review summary
- GitHub export
- Jira export
- bundle export
- debug bundle export

Constraints:
- do not over-design the UI
- keep the review pane readable at smaller widths
- no backend
- no secret leakage in logs

Validation:
- run:
  - `dotnet restore windows/BugNarrator.Windows.sln`
  - `dotnet build windows/BugNarrator.Windows.sln -c Debug`
  - `dotnet test windows/BugNarrator.Windows.sln -c Debug`
- manually validate:
  - stop recording with an API key configured triggers transcription and opens the session library
  - stop recording with no API key configured still saves a completed session and shows a clear fallback state
  - completed sessions appear in the library
  - search, sort, and filter work on saved sessions
  - review tabs switch correctly
  - screenshot preview works for sessions that contain screenshot artifacts
  - app survives transcription failures cleanly
- inspect:
  - `%LocalAppData%\BugNarrator\Sessions\`
  - `%LocalAppData%\BugNarrator\Logs\windows-shell.log`

Documentation updates required:
1. update `windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md` with the actual Milestone 5 findings, scope changes, and remaining risks
2. update `windows/docs/WINDOWS_VALIDATION_CHECKLIST.md` with Milestone 5 validation steps, artifacts, and failure cases
3. update `windows/README.md` with the current Windows milestone status
4. clearly note anything deferred to Milestone 6

Return:
- files changed
- what was implemented versus deferred
- storage model used
- validation performed and the exact results
- artifact paths produced during validation
- remaining review-workspace gaps
- docs updated and why
```

### Prompt 6: Extraction, Exports, Diagnostics, Packaging

```md
Use the current Windows branch plus these repo documents as the source of truth:

- `README.md`
- `docs/UserGuide.md`
- `docs/CROSS_PLATFORM_GUIDELINES.md`
- `windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md`
- `windows/docs/WINDOWS_VALIDATION_CHECKLIST.md`
- `windows/docs/WINDOWS_SIGNING_AND_RELEASE.md`

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

### Prompt 7: Windows Global Hotkeys Parity

```md
Use the current Windows branch plus these repo documents as the source of truth:

- `README.md`
- `CHANGELOG.md`
- `docs/UserGuide.md`
- `docs/QA_CHECKLIST.md`
- `docs/CROSS_PLATFORM_GUIDELINES.md`
- `windows/README.md`
- `windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md`
- `windows/docs/WINDOWS_VALIDATION_CHECKLIST.md`

Execute the next Windows post-MVP parity milestone for BugNarrator: `Windows Global Hotkeys`.

Objective:
Close the largest remaining macOS parity gap by adding optional, user-assigned Windows global hotkeys for the live recording workflow without destabilizing the tray app, recording lifecycle, screenshot capture, or settings experience.

Product rules to preserve:
- global hotkeys are optional
- hotkeys start unassigned as `Not Set`
- do not add built-in default shortcuts
- do not add a `Default` button or shortcut suggestions
- the recording controls window remains the primary control surface during a live session
- this milestone covers only:
  - `Start Recording`
  - `Stop Recording`
  - `Capture Screenshot`

Execution workflow:
1. discovery
   - audit the current Windows tray shell, settings flow, recording lifecycle, and app startup/shutdown path
   - review the existing macOS hotkey behavior and user-facing expectations from the source-of-truth docs
   - identify the smallest Windows architecture change that supports registration, persistence, editing, conflict handling, and clean teardown
2. design
   - define the hotkey action model and persistence shape
   - keep reusable action concepts and validation rules portable where practical
   - keep key translation, registration, message handling, and OS integration Windows-specific
3. implementation
   - build the Windows hotkey registration service
   - wire hotkeys into the existing recording lifecycle actions
   - add settings UI for assign, clear, and conflict/error feedback
   - make sure app startup, settings edits, and app shutdown all register/unregister cleanly
4. validation
   - run automated validation
   - manually validate tray-only and out-of-focus usage on a real Windows desktop
   - verify duplicate-assignment and OS-conflict behavior
5. documentation
   - update roadmap, validation checklist, README, and user-facing usage notes with actual findings and any deferred work

Required deliverables:
1. implement Windows global hotkey support for:
   - `Start Recording`
   - `Stop Recording`
   - `Capture Screenshot`
2. persist hotkey settings locally with all actions defaulting to `Not Set`
3. add a Windows hotkey registration service that:
   - registers assigned shortcuts on startup
   - re-registers after settings changes
   - unregisters on shutdown/dispose
   - survives window open/close cycles and tray-first usage
4. add settings UI that allows the user to:
   - view the current shortcut for each action
   - assign a new shortcut
   - clear a shortcut back to `Not Set`
   - see a clear error when a shortcut is invalid or unavailable
5. reject duplicate in-app assignments with a clear message instead of silently overriding another action
6. reject invalid shortcuts such as modifier-only input
7. handle OS-level registration failures cleanly and visibly without crashing the app
8. route hotkey actions through the existing recording lifecycle flow instead of bypassing it
9. add diagnostics for:
   - registration success
   - registration failure
   - duplicate assignment rejection
   - hotkey invocation
10. preserve current behavior for recording controls, screenshot capture, session library, and tray lifecycle

Behavior requirements:
- assigned hotkeys must work while BugNarrator is in the tray and another app has focus
- `Start Recording` should only succeed when the app is in a valid start state
- `Stop Recording` should only succeed when a recording is active
- `Capture Screenshot` should only succeed when screenshot capture is allowed by the current session state
- invalid hotkey presses or unavailable actions must not crash the app
- if a stored shortcut cannot be registered on startup, the app must surface a clear status and remain usable
- changing a shortcut in settings should immediately update active registration
- relaunching the app should restore previously assigned hotkeys
- single-instance behavior must continue to work correctly

Constraints:
- prefer a standard Windows global hotkey registration approach rather than a low-level keyboard hook unless a documented limitation forces otherwise
- require at least one modifier for any assigned shortcut
- keep Windows-specific key handling and registration out of `BugNarrator.Core`
- do not add new workflow actions such as `Open Session Library`, `Open Settings`, or marker hotkeys in this milestone
- do not re-open already completed parity surfaces unless needed for hotkey integration
- do not weaken any hardening/security work already completed
- do not leak secrets or sensitive settings values in logs

Explicit non-goals:
- transcription changes
- issue extraction changes
- GitHub/Jira export changes
- packaging/signing changes
- screenshot overlay redesign
- major recording controls UI redesign beyond what is required to expose or explain hotkey status

Validation:
- run:
  - `dotnet restore windows/BugNarrator.Windows.sln`
  - `dotnet build windows/BugNarrator.Windows.sln -c Debug`
  - `dotnet test windows/BugNarrator.Windows.sln -c Debug`
- manually validate on Windows:
  - on a fresh settings state, `Start Recording`, `Stop Recording`, and `Capture Screenshot` all show `Not Set`
  - assign each shortcut and verify it registers successfully
  - trigger start, stop, and screenshot from another app while BugNarrator is not focused
  - clear an assigned shortcut and verify it returns to `Not Set` and no longer triggers
  - assign the same shortcut to two actions and verify the conflict is rejected with a clear message
  - attempt an invalid shortcut and verify it is rejected cleanly
  - verify settings changes take effect immediately without relaunch
  - relaunch the app and verify assigned shortcuts persist and re-register
  - verify tray-first use still works and single-instance behavior is unchanged
- inspect:
  - `%LocalAppData%\BugNarrator\Logs\windows-shell.log`
  - the Windows settings storage file(s) used for hotkey persistence

Documentation updates required:
1. update `windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md` with the actual hotkey milestone outcome, architecture decisions, risks, and follow-up items
2. update `windows/docs/WINDOWS_VALIDATION_CHECKLIST.md` with the hotkey validation scenarios, conflict cases, and failure expectations
3. update `windows/README.md` with the current Windows parity status and the rule that hotkeys are optional and unassigned by default
4. update `docs/UserGuide.md` if the Windows user flow now includes assigning and using hotkeys
5. clearly note anything deferred beyond this milestone

Return:
- files changed
- what was implemented versus deferred
- hotkey registration API choice and why
- storage model used for hotkey settings
- validation performed and the exact results
- any manual validation gaps that still remain
- known risks, especially around reserved shortcuts, keyboard layouts, focus behavior, and registration conflicts
- docs updated and why
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
