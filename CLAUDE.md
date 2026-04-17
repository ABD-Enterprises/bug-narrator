# CLAUDE.md — BugNarrator

## What This Repo Is

BugNarrator is a desktop tool for narrated software testing sessions. macOS app (Swift/SwiftUI, menu bar) is production at v1.0.23. Windows app (C#/.NET 8/WPF, system tray) is in development.

Core workflow: `record -> review -> refine -> export`

## Build & Test (macOS)

```bash
xcodegen generate                          # only if project.yml changed
xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO test
./scripts/release_smoke_test.sh            # pre-release validation
./scripts/accessibility_regression_check.sh # accessibility tripwire
```

## Build & Test (Windows)

```powershell
./windows/scripts/build-windows.ps1 -Configuration Debug
./windows/scripts/test-windows.ps1 -Configuration Debug
./windows/scripts/package-windows.ps1 -Configuration Release
./windows/scripts/validate-windows-package.ps1 -Runtime win-x64
```

## Key Files

- Product spec: `docs/architecture/product-spec.md`
- Roadmap state: `docs/roadmap/state.json`
- OS-aware roadmap: `docs/roadmap/codex-roadmap.md`
- Parity matrix: `docs/architecture/parity-matrix.md`
- Changelog: `CHANGELOG.md`
- macOS app entry: `Sources/BugNarrator/BugNarratorApp.swift`
- macOS state: `Sources/BugNarrator/AppState.swift`
- Windows solution: `windows/BugNarrator.Windows.sln`

## Architecture

- macOS: `Sources/BugNarrator/{Models,Services,Views,Utilities}/`
- Windows: `windows/src/{BugNarrator.Core,BugNarrator.Windows,BugNarrator.Windows.Services}/`
- Tests: `Tests/BugNarratorTests/` (macOS), `windows/tests/` (Windows)
- CI: `.github/workflows/ci.yml` (docs + Windows on PRs, no macOS CI on PRs)
- Release: `.github/workflows/release.yml` (manual dispatch, macOS DMG only)

## Current State

- Current phase: `RR-002 Windows Runtime Validation And Hardening`
- Open bug: BN-P1-014 — exported bundles can omit screenshots the transcript references

## Rules

- Run tests after code changes
- Do not bump version without explicit instruction
- Do not modify the product spec without explicit instruction
- Update parity matrix when Windows features change
- Update roadmap state.json when completing phases
