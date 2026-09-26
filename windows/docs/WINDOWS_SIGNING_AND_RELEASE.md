# BugNarrator Windows Signing And Release

## Purpose

This document describes the current Windows packaging, signing, and release workflow for BugNarrator.

## Current Packaging Format

The current branch packages BugNarrator as a zipped `dotnet publish` output using:

- `windows/scripts/package-windows.ps1`
- `windows/scripts/release-windows-phase-b.ps1` now stages the future public-release path and reports blockers honestly even when installer/signing prerequisites are missing on the current machine

That script publishes `BugNarrator.Windows.csproj` for `win-x64` by default and creates:

- `windows/artifacts/publish/<runtime>/`
- `windows/artifacts/packages/BugNarrator-windows-<runtime>.zip`

This is sufficient for internal validation and external handoff while the public installer path is still blocked.

CI now validates the packaged zip contents and launches the packaged Windows executable in a headless smoke mode before uploading the Windows artifact from `windows-latest`. This improves release-candidate confidence, but it does not replace a real desktop validation pass for tray, microphone, screenshot, or hotkey behavior.

## Build And Test

Run:

- `powershell -ExecutionPolicy Bypass -File windows/scripts/build-windows.ps1 -Configuration Debug`
- `powershell -ExecutionPolicy Bypass -File windows/scripts/test-windows.ps1 -Configuration Debug`
- `powershell -ExecutionPolicy Bypass -File windows/scripts/validate-windows-package.ps1 -Runtime win-x64`
- `powershell -ExecutionPolicy Bypass -File windows/scripts/validate-windows-package.ps1 -Runtime win-x64` now also runs the packaged executable with `--smoke-output <path>` and validates the emitted JSON report.

For release packaging, run:

- `powershell -ExecutionPolicy Bypass -File windows/scripts/package-windows.ps1 -Configuration Release`

## Signing

The repo now includes:

- `windows/scripts/sign-windows.ps1`
- `windows/scripts/build-windows-installer.ps1`
- `windows/installer/BugNarrator.iss`
- `windows/scripts/release-windows-phase-b.ps1`

Required environment variables:

- `BUGNARRATOR_CERT_PATH`
- `BUGNARRATOR_CERT_PASSWORD`

The signing script also expects `signtool.exe` to be available on `PATH`, or you can pass `-SignToolPath`.

Example:

```powershell
powershell -ExecutionPolicy Bypass -File windows/scripts/sign-windows.ps1 `
  -FilePath windows/artifacts/publish/win-x64/BugNarrator.Windows.exe
```

## Current Release Blocker

The current blockers for public signed distribution are the real installer/signing prerequisites on the machine that runs the release:

- Inno Setup 6 or another installer compiler path
- `signtool.exe`
- a real code-signing certificate and password

The repo now contains the Inno Setup installer template and a public-release orchestration script, but the public Windows release stays blocked until those prerequisites exist.

This branch still does not include:

- a checked-in certificate
- a CI signing secret
- a checked-in installer compiler

Until a real code-signing certificate is provisioned, release candidates should be treated as internal or trusted-tester artifacts.

## Recommended Next Release Steps

1. Install Inno Setup 6 or pass its compiler path to `windows/scripts/build-windows-installer.ps1`.
2. Provision a Windows code-signing certificate and store it outside the repo.
3. Ensure `signtool.exe` is available from the Windows SDK.
4. Run `windows/scripts/release-windows-phase-b.ps1`.
5. If the generated status is `ready`, validate the signed installer on a clean Windows machine.
6. Upload the signed installer, checksums, and notes to GitHub Releases.
