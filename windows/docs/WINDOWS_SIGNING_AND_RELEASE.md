# BugNarrator Windows Signing And Release

## Purpose

This document describes the current Windows packaging, signing, and release workflow for BugNarrator.

## Current Packaging Format

The current branch packages BugNarrator as a zipped self-contained `dotnet publish` output using:

- `windows/scripts/package-windows.ps1`

That script publishes `BugNarrator.Windows.csproj` for `win-x64` by default and creates:

- `windows/artifacts/publish/<runtime>/`
- `windows/artifacts/packages/BugNarrator-windows-<runtime>.zip`

This is sufficient for internal validation and external handoff while installer work remains deferred. The first tester release format is a zip that contains a signed `BugNarrator.Windows.exe`, package validation evidence, and release notes. Installer or MSIX authoring remains a follow-up if tester distribution needs a more guided install path.

CI now validates the packaged zip contents and writes a structured package smoke report before uploading the Windows artifact from `windows-latest`. This improves release-candidate confidence, but it does not replace a real desktop validation pass for tray, microphone, screenshot, or hotkey behavior.

## Build And Test

Run:

- `powershell -ExecutionPolicy Bypass -File windows/scripts/build-windows.ps1 -Configuration Debug`
- `powershell -ExecutionPolicy Bypass -File windows/scripts/test-windows.ps1 -Configuration Debug`
- `powershell -ExecutionPolicy Bypass -File windows/scripts/validate-windows-package.ps1 -Runtime win-x64`
- `powershell -ExecutionPolicy Bypass -File windows/scripts/validate-windows-package.ps1 -Runtime win-x64` now also runs the packaged executable with `--smoke-output <path>` and validates the emitted JSON report.

For release packaging, run:

- `powershell -ExecutionPolicy Bypass -File windows/scripts/package-windows.ps1 -Configuration Release`

For a signed tester release package, run on Windows:

- `powershell -ExecutionPolicy Bypass -File windows/scripts/release-windows-tester.ps1 -Runtime win-x64`

## Signing

The repo now includes:

- `windows/scripts/sign-windows.ps1`
- `windows/scripts/verify-windows-signature.ps1`
- `windows/scripts/release-windows-tester.ps1`
- `.github/workflows/windows-tester-release.yml`

Required environment variables:

- `BUGNARRATOR_CERT_PATH`
- `BUGNARRATOR_CERT_PASSWORD`

The signing script also expects `signtool.exe` to be available on `PATH`, or you can pass `-SignToolPath`.

Example:

```powershell
powershell -ExecutionPolicy Bypass -File windows/scripts/sign-windows.ps1 `
  -FilePath windows/artifacts/publish/win-x64/BugNarrator.Windows.exe
```

The release script packages the app, signs `BugNarrator.Windows.exe`, verifies the Authenticode signature with `Get-AuthenticodeSignature`, repacks the signed publish output into `windows/artifacts/packages/BugNarrator-windows-win-x64.zip`, reruns package validation, and writes:

- `windows/artifacts/validation/BugNarrator-windows-win-x64-signature.json`
- `windows/artifacts/validation/BugNarrator-windows-win-x64-validation.json`
- `windows/artifacts/validation/BugNarrator-windows-win-x64-release-notes.md`

The GitHub Actions workflow is manual (`workflow_dispatch`) and requires these repository secrets:

- `BUGNARRATOR_WINDOWS_CERT_BASE64`: base64-encoded PFX certificate
- `BUGNARRATOR_WINDOWS_CERT_PASSWORD`: PFX password

## Current Release Blocker

The current blocker for public signed distribution is certificate availability, not the script entrypoints.

This branch does not include:

- a checked-in certificate
- a CI signing secret
- an installer authoring pipeline

Until a real code-signing certificate is provisioned and configured in the release environment, the signed tester release workflow will fail intentionally rather than producing an unsigned artifact that looks signed.

## Recommended Next Release Steps

1. Provision a Windows code-signing certificate and store it outside the repo.
2. Add `BUGNARRATOR_WINDOWS_CERT_BASE64` and `BUGNARRATOR_WINDOWS_CERT_PASSWORD` as GitHub repository secrets, or set `BUGNARRATOR_CERT_PATH` and `BUGNARRATOR_CERT_PASSWORD` locally.
3. Produce a signed `Release` package with `windows/scripts/release-windows-tester.ps1`.
4. Validate the signed build on a clean Windows machine.
5. Upload the zip package, signature report, package validation report, and validation notes to GitHub Releases, or use the manual `Windows Tester Release` workflow.

Installer EXE or MSIX packaging should be tracked separately if tester feedback shows that a signed zip is not enough.
