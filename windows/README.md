# BugNarrator Windows Workspace

This directory contains the Windows implementation workspace for BugNarrator.

Source-of-truth documents for Windows work:

- [Canonical Product Spec](../docs/architecture/product-spec.md)
- [Cross-Platform Parity Matrix](../docs/architecture/parity-matrix.md)
- [Windows Implementation Roadmap](docs/WINDOWS_IMPLEMENTATION_ROADMAP.md)
- [Windows Validation Checklist](docs/WINDOWS_VALIDATION_CHECKLIST.md)
- [Windows Signing And Release](docs/WINDOWS_SIGNING_AND_RELEASE.md)
- [Cross-Platform Guidelines](../docs/CROSS_PLATFORM_GUIDELINES.md)

## Current Workspace Status

The Windows workspace currently includes:

- solution and project scaffolding
- tray shell and single-instance wiring
- recording lifecycle scaffolding
- screenshot-capture scaffolding
- Windows validation guidance for real Windows machines or VMs

The next Windows priority is runtime validation on Windows, followed by the next roadmap milestone.

## Build Notes
This workspace targets:

- C#
- .NET 8
- WPF for the Windows UI shell

WPF restore, build, and launch validation must happen on Windows. This macOS workspace can prepare the project structure and non-Windows-specific files, but it cannot honestly validate the Windows UI project.

## Intended Windows Commands
Run these on a Windows machine with the .NET 8 SDK installed:

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
powershell -ExecutionPolicy Bypass -File windows/scripts/validate-windows-package.ps1 -Runtime win-x64
```

Current Windows milestone status:

- Milestone 4 screenshot capture is implemented, including screenshot preflight, drag-select overlay, deterministic screenshot naming, screenshot metadata persistence, and screenshot-linked timeline moments
- Milestone 5 transcription and review is implemented, including DPAPI-backed OpenAI API key storage, local transcription settings, completed `session.json` plus `transcript.md` persistence, and a WPF session library with transcript, screenshot, summary, and extracted-issue review tabs
- Milestone 6 is implemented, including OpenAI issue extraction, editable/selectable draft issues, local session bundle export, local debug bundle export, experimental GitHub export, experimental Jira export, packaging scripts, and Windows signing/release documentation
- the post-MVP macOS parity milestone for the session library is implemented, including `Today`, `Yesterday`, `Last 7 Days`, `Last 30 Days`, `All Sessions`, and `Custom Date Range` filters plus permanent local session deletion
- the post-MVP Windows global hotkey parity milestone is implemented, including optional `Start Recording`, `Stop Recording`, and `Capture Screenshot` shortcuts that start as `Not Set`, save locally, register on app startup, and surface clear conflict/unavailable status in Settings
- the post-MVP hardening milestone is implemented, including shared atomic file writes, root-bound session path validation, corrupted-secret tolerance, diagnostic redaction, safer export/session loading, friendlier network failure messages, and defensive screenshot preview handling
- stopping a recording now saves the session even when no OpenAI API key is configured and preserves a clear failure state if transcription fails
- automated coverage currently includes `9` core tests and `27` Windows tests
- `windows/scripts/package-windows.ps1` currently produces a zipped `dotnet publish` artifact at `windows/artifacts/packages/BugNarrator-windows-win-x64.zip`
- `windows/scripts/validate-windows-package.ps1` validates that the published Windows zip contains the expected executable, DLL, and runtime metadata before CI treats the package as healthy
- manual validation is still required for live OpenAI transcription, live issue extraction, overlay/display behavior, DPI scaling, multi-monitor screenshot preview behavior, hotkey behavior under reserved shortcuts and alternate keyboard layouts, session deletion on a real desktop, corrupted-local-state recovery, and real GitHub/Jira credentials on a Windows desktop
