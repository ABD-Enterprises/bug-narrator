# AGENTS.md — BugNarrator

This file configures AI coding agents (Codex, etc.) for the BugNarrator repo.

## What This Repo Is

BugNarrator is a desktop tool for narrated software testing sessions. It records audio, captures screenshots, transcribes via OpenAI, extracts issues with AI, and exports session bundles. The core workflow is `record -> review -> refine -> export`.

- **macOS app**: Swift 6.0 / SwiftUI / AppKit, menu bar app, macOS 14+
- **Windows app**: C# / .NET 8 / WPF, system tray app (in progress)
- **Current version**: 1.0.22 (macOS production, Windows in development)

## OS Detection

This is a dual-platform project. **Check which OS you're running on before doing any work.** The platforms have completely separate toolchains and codebases.

### If Running on macOS

You can work on:
- The Swift/SwiftUI macOS app in `Sources/BugNarrator/`
- macOS tests in `Tests/BugNarratorTests/`
- Build scripts in `scripts/`
- Documentation in `docs/` and `site/`
- CI workflow files in `.github/workflows/`

Build and test commands:
```bash
xcodegen generate  # only if project.yml changed
xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO test
./scripts/release_smoke_test.sh
./scripts/accessibility_regression_check.sh
```

You CANNOT:
- Build, test, or validate the Windows .NET workspace
- Run PowerShell build scripts
- Validate Windows package artifacts

### If Running on Windows

You can work on:
- The C#/.NET 8 Windows app in `windows/src/`
- Windows tests in `windows/tests/`
- Windows build/package scripts in `windows/scripts/`
- Documentation in `docs/` and `site/`
- CI workflow files in `.github/workflows/`
- Platform-neutral models in `windows/src/BugNarrator.Core/`

Build and test commands:
```powershell
./windows/scripts/build-windows.ps1 -Configuration Debug
./windows/scripts/test-windows.ps1 -Configuration Debug
./windows/scripts/package-windows.ps1 -Configuration Release
./windows/scripts/validate-windows-package.ps1 -Runtime win-x64
```

You CANNOT:
- Build, test, or validate the macOS Swift app
- Run xcodebuild, xcodegen, or any Xcode tooling
- Validate DMG packaging, code signing, or notarization
- Run the macOS accessibility regression script

### Either OS

You can always work on:
- Markdown documentation in `docs/`
- Docusaurus site content in `site/` (requires Node 22)
- CI workflow YAML in `.github/workflows/`
- Roadmap state in `docs/roadmap/`
- Parity matrix in `docs/architecture/parity-matrix.md`

## Key Source of Truth Documents

- **Product spec**: `docs/architecture/product-spec.md`
- **Roadmap state**: `docs/roadmap/state.json`
- **Parity matrix**: `docs/architecture/parity-matrix.md`
- **OS-aware roadmap**: `docs/roadmap/codex-roadmap.md`
- **Changelog**: `CHANGELOG.md`
- **Windows implementation plan**: `windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md`

## Current Phase

`RR-002 Windows Runtime Validation And Hardening` — validate WPF tray shell, recording lifecycle, screenshot capture, and hotkey registration on real Windows. CI scaffolding is done; real desktop validation is the gap.

## Open Bugs

- **BN-P1-014** (macOS): Exported session bundles can omit screenshots that the transcript references. Suspected area: `SessionBundleExportService` copies only files still on disk at export time.

## Architecture

### macOS (Sources/BugNarrator/)
- `Models/` — data models (sessions, issues, transcripts)
- `Services/` — 22 service files (recording, permissions, export, transcription, etc.)
- `Views/` — SwiftUI views
- `Utilities/` — session library, single-instance, diagnostics
- `AppState.swift` — central state orchestration
- `BugNarratorApp.swift` — app entry point

### Windows (windows/src/)
- `BugNarrator.Core/` — platform-neutral models (shared)
- `BugNarrator.Windows/` — WPF UI shell, tray integration, view models
- `BugNarrator.Windows.Services/` — Windows-specific services (audio, screenshots, hotkeys, secrets)

## CI Pipeline

| Job | Runner | Trigger |
| --- | --- | --- |
| `docs-site-validation` | ubuntu-latest | push + PRs |
| `windows-workspace-validation` | windows-latest | push + PRs |
| `package-macos` (release only) | macos-15 | manual workflow_dispatch |

No macOS CI job runs on PRs. macOS validation is release-time only.

## Rules

- Do not modify `docs/architecture/product-spec.md` without explicit instruction
- Do not bump the version in `project.yml` or CHANGELOG without explicit instruction
- Do not create or modify release artifacts without explicit instruction
- Always run tests after code changes
- Keep the parity matrix updated when Windows features change
- Update `docs/roadmap/state.json` when completing or starting phases
