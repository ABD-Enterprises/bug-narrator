# Development Setup

This document is the canonical development setup guide for BugNarrator maintainers.

## Repository Prerequisites

macOS development prerequisites:

- macOS 14 or later
- Xcode
- `xcodebuild`
- `xcodegen`
- Python 3 for DMG packaging helpers

Windows workspace prerequisites:

- .NET 8 SDK
- Windows for honest WPF build and runtime validation
- Visual Studio 2022 with `.NET desktop development` for the easiest local workflow

Optional local tools:

- `dmgbuild` inside `build/dmg-venv`
- GitHub CLI for release work

## Clone And Inspect

```bash
git clone https://github.com/deffenda/bug-narrator.git
cd bug-narrator
git status
```

## macOS App Setup

If `project.yml` changed, regenerate the Xcode project:

```bash
xcodegen generate
```

Build the app locally:

```bash
xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Run tests:

```bash
xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO test
```

## Local Release Validation

Recommended release-readiness baseline:

```bash
./scripts/release_smoke_test.sh
```

Unsigned DMG packaging:

```bash
./scripts/build_dmg.sh
```

If local build copies are cluttering macOS permissions or Launch Services:

```bash
./scripts/cleanup_local_build_apps.sh
```

## Windows Workspace Setup

The Windows workspace is intentionally isolated under `windows/`.

On a Windows machine:

```powershell
dotnet restore windows/BugNarrator.Windows.sln
dotnet build windows/BugNarrator.Windows.sln -c Debug
dotnet test windows/tests/BugNarrator.Core.Tests/BugNarrator.Core.Tests.csproj -c Debug
```

On macOS, you can prepare or edit the Windows workspace, but you cannot honestly validate the WPF app shell.

## Development Rules

- keep the macOS app stable while Windows work evolves
- follow [docs/architecture/product-spec.md](../architecture/product-spec.md) for product behavior and terminology
- follow [docs/CROSS_PLATFORM_GUIDELINES.md](../CROSS_PLATFORM_GUIDELINES.md) for parity decisions
- prefer secure local secret storage patterns
- never commit real API keys, tokens, or notarization credentials
- update roadmap state when phase decisions, risks, or opportunities change

## Related Docs

- [Product Spec](../architecture/product-spec.md)
- [Architecture Overview](../architecture/overview.md)
- [Testing Guide](../testing/testing.md)
- [Release Process](../release/release-process.md)
- [Windows Workspace README](../../windows/README.md)
