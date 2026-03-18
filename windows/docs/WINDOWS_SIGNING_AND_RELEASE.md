# BugNarrator Windows Signing And Release

## Purpose

This document describes the current Windows packaging, signing, and release workflow for BugNarrator.

## Current Packaging Format

The current branch packages BugNarrator as a zipped `dotnet publish` output using:

- `windows/scripts/package-windows.ps1`

That script publishes `BugNarrator.Windows.csproj` for `win-x64` by default and creates:

- `windows/artifacts/publish/<runtime>/`
- `windows/artifacts/packages/BugNarrator-windows-<runtime>.zip`

This is sufficient for internal validation and external handoff while installer work remains deferred.

## Build And Test

Run:

- `powershell -ExecutionPolicy Bypass -File windows/scripts/build-windows.ps1 -Configuration Debug`
- `powershell -ExecutionPolicy Bypass -File windows/scripts/test-windows.ps1 -Configuration Debug`

For release packaging, run:

- `powershell -ExecutionPolicy Bypass -File windows/scripts/package-windows.ps1 -Configuration Release`

## Signing

The repo now includes:

- `windows/scripts/sign-windows.ps1`

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

The current blocker for public signed distribution is certificate availability, not the script entrypoints.

This branch does not include:

- a checked-in certificate
- a CI signing secret
- an installer authoring pipeline

Until a real code-signing certificate is provisioned, release candidates should be treated as internal or trusted-tester artifacts.

## Recommended Next Release Steps

1. Provision a Windows code-signing certificate and store it outside the repo.
2. Produce a `Release` package with `windows/scripts/package-windows.ps1`.
3. Sign `BugNarrator.Windows.exe` and any additional distributables with `windows/scripts/sign-windows.ps1`.
4. Validate the signed build on a clean Windows machine.
5. Upload the zip package and validation notes to GitHub Releases.
