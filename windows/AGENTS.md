# AGENTS.md — BugNarrator Windows Workspace

This file provides Windows-specific guidance for AI agents working in the `windows/` subtree.

See the root `AGENTS.md` for full project context and OS detection rules.

## Workspace Structure

```
windows/
├── src/
│   ├── BugNarrator.Core/              # Platform-neutral models (shared)
│   ├── BugNarrator.Windows/           # WPF UI shell, tray, view models
│   └── BugNarrator.Windows.Services/  # Windows services (audio, screenshots, hotkeys, secrets)
├── tests/
│   ├── BugNarrator.Core.Tests/        # 6+ model/formatting tests
│   └── BugNarrator.Windows.Tests/     # 23+ lifecycle/hotkey/export/smoke tests
├── scripts/
│   ├── build-windows.ps1
│   ├── test-windows.ps1
│   ├── package-windows.ps1
│   └── validate-windows-package.ps1
├── docs/
│   ├── WINDOWS_IMPLEMENTATION_ROADMAP.md
│   ├── WINDOWS_VALIDATION_CHECKLIST.md
│   └── WINDOWS_SIGNING_AND_RELEASE.md
└── BugNarrator.Windows.sln
```

## Build & Test

```powershell
./windows/scripts/build-windows.ps1 -Configuration Debug
./windows/scripts/test-windows.ps1 -Configuration Debug
./windows/scripts/test-windows.ps1 -Configuration Debug -NoBuild  # skip rebuild
./windows/scripts/package-windows.ps1 -Configuration Release
./windows/scripts/validate-windows-package.ps1 -Runtime win-x64
```

## Current Priority: RR-002

Validate on real Windows hardware:
1. WPF tray shell starts and shows the tray icon
2. Recording controls window opens from the tray
3. Microphone recording starts/stops cleanly
4. Screenshot region selection works
5. Global hotkeys register and fire
6. Single-instance enforcement prevents duplicates
7. Packaged zip artifact runs outside the build directory

## Next Phases (Windows)

- **WIN-005**: Transcription client, OpenAI key storage, session library, review workspace
- **WIN-006**: Summary generation, issue extraction, session bundle export, GitHub/Jira export

## Tech Stack

- C# / .NET 8
- WPF for desktop UI
- CommunityToolkit.Mvvm
- NAudio or Media Foundation for audio
- Windows Credential Manager / DPAPI for secrets
- Microsoft.Extensions.Logging

## Rules

- Always run tests after changes: `./windows/scripts/test-windows.ps1 -Configuration Debug`
- Keep `BugNarrator.Core` platform-neutral — no Windows-specific types there
- Update `docs/architecture/parity-matrix.md` when feature status changes
- Update `docs/roadmap/state.json` when completing validation items
