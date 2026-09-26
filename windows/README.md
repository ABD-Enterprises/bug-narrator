# BugNarrator Windows Workspace

This directory contains the Windows implementation workspace for BugNarrator.

Source-of-truth documents for Windows work:

- [Canonical Product Spec](../docs/architecture/product-spec.md)
- [Cross-Platform Parity Matrix](../docs/architecture/parity-matrix.md)
- [Windows Codex Handoff](docs/WINDOWS_CODEX_HANDOFF.md)
- [Windows Implementation Roadmap](docs/WINDOWS_IMPLEMENTATION_ROADMAP.md)
- [Windows Validation Checklist](docs/WINDOWS_VALIDATION_CHECKLIST.md)
- [Windows Signing And Release](docs/WINDOWS_SIGNING_AND_RELEASE.md)
- [Cross-Platform Guidelines](../docs/CROSS_PLATFORM_GUIDELINES.md)

## Current Workspace Status

The Windows workspace currently includes:

- solution and project scaffolding
- tray shell and single-instance runtime validation on a real Windows desktop
- recording lifecycle runtime validation against a real microphone state
- screenshot overlay and region-capture runtime validation on a real Windows desktop
- out-of-focus global hotkey validation plus reserved-shortcut rejection on Windows
- preserved-session retry and generated review summary parity on the current branch
- a native `Help And Support` surface with docs, release, reporting, repository, support, and debug-bundle actions
- keyboard-first accessibility hardening plus microphone and screenshot recovery guidance
- a public-release scaffold with a blocker-aware Phase B status report for installer or signing prerequisites
- Windows validation guidance for real Windows machines or VMs

The RR-002 runtime blocker has now been exercised on Windows. The remaining manual gaps are narrower: live OpenAI and Jira provider flows, alternate keyboard layout or mixed-display coverage on a suitable machine, and broader signed public-release proof.

If Codex is taking over Windows development, start with [Windows Codex Handoff](docs/WINDOWS_CODEX_HANDOFF.md).

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
powershell -ExecutionPolicy Bypass -File windows/scripts/invoke-windows-codex-handoff.ps1 -RunBaseline
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
- the `WIN-007` recovery and summary parity cycle is implemented, including retry-needed session states, retry transcription from the session library, retry metadata persistence, and generated review summary shaping in the completed session model
- the `WIN-008` launch and support parity cycle is implemented, including the native `Help And Support` surface, shell-launched docs/changelog/releases/issues/repository/support links, support-oriented debug-bundle discoverability, and explicit close behavior in Recording Controls
- the `WIN-009` accessibility and permission-guidance parity cycle is implemented, including accessibility labels and live-status semantics across the code-built WPF surfaces plus Windows settings links and recovery guidance for microphone and screenshot failures
- stopping a recording now saves the session even when no OpenAI API key is configured and preserves a clear failure state if transcription fails
- automated coverage currently includes `11` core tests and `34` Windows tests
- `windows/scripts/package-windows.ps1` currently produces a self-contained zipped `dotnet publish` artifact at `windows/artifacts/packages/BugNarrator-windows-win-x64.zip`
- `windows/scripts/validate-windows-package.ps1` validates that the published Windows zip contains the expected executable, DLL, and runtime metadata, checks packaged-file hash parity against the publish output, then launches the packaged app in a headless smoke mode that writes a structured report and exits cleanly
- `windows/scripts/invoke-windows-codex-handoff.ps1` writes `windows/artifacts/handoff/windows-codex-handoff.json` so a Codex instance on Windows can load the active phase, tasks, risks, artifacts, and recommended commands from one report
- `windows/scripts/release-windows-phase-b.ps1` stages the public Windows release path, writes `windows/artifacts/releases/public/<label>/public-release-status.json`, and stops at an explicit `blocked` status when installer or signing prerequisites are missing
- CI now uploads `bugnarrator-windows-package`, `bugnarrator-windows-validation`, and `bugnarrator-windows-handoff` artifacts from the Windows runner
- the April 4, 2026 Windows desktop pass confirmed the BugNarrator tray icon in the system-tray overflow, duplicate-instance focus handoff, microphone-backed recording, screenshot overlay region capture, out-of-focus hotkeys from Notepad focus, and reserved shortcut rejection for `Shift+Win+S`
- the April 4, 2026 runtime follow-up also confirmed retry-needed sessions and `Retry Transcription` guidance when no OpenAI key is configured, real `Export Debug Bundle` success from the session library, live GitHub export through the Windows service path into a disposable private repository, and production-path proof for session deletion plus corrupted-local-state bundle safety
- the current public Windows release path is still blocked on Inno Setup, `signtool.exe`, and real certificate inputs on the release machine
- manual validation is still required for live OpenAI transcription, live issue extraction, live Jira export, DPI scaling, multi-monitor screenshot preview behavior, alternate keyboard layouts on a machine with more than one installed layout, and signed installer install, relaunch, reinstall, and uninstall behavior on a clean Windows machine or VM
