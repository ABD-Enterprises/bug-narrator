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

## Signing With Azure Trusted Signing

Azure Trusted Signing is the preferred path: there is no PFX file or password to manage, and the
certificate is short-lived and cloud-held. It is wired through:

- `windows/scripts/sign-windows-trustedsigning.ps1`
- the `-UseTrustedSigning` switch on `windows/scripts/release-windows-tester.ps1`

It signs with `signtool` plus the `Azure.CodeSigning` dlib (from the
`Microsoft.Trusted.Signing.Client` NuGet package, restored on demand if not already cached).
Authentication uses Azure.Identity `DefaultAzureCredential`, so it works from a local `az login`
session, or from `AZURE_TENANT_ID` / `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` in CI.

Prerequisites:

- the signing identity holds the **Trusted Signing Certificate Profile Signer** data-plane role on
  the account (Azure has since renamed this "Artifact Signing Certificate Profile Signer")
- a certificate profile exists on the account; a `PublicTrust` profile requires a **completed
  identity validation**

Current BugNarrator account (in subscription `7fb728a1-...`, tenant `alanabdenterprises.onmicrosoft.com`):

- Endpoint: `https://wus3.codesigning.azure.net/`
- Account: `bugnarrator-signing`
- Certificate profile: `bugnarrator-public` (PublicTrust) — these are the script defaults

Sign a single file:

```powershell
powershell -ExecutionPolicy Bypass -File windows/scripts/sign-windows-trustedsigning.ps1 `
  -FilePath windows/artifacts/publish/win-x64/BugNarrator.Windows.exe
```

Produce a signed tester release with Trusted Signing:

```powershell
powershell -ExecutionPolicy Bypass -File windows/scripts/release-windows-tester.ps1 `
  -Runtime win-x64 -UseTrustedSigning
```

The release script's verify/repack/validate/release-note steps are unchanged — Authenticode
verification via `Get-AuthenticodeSignature` is signing-method agnostic.

## Current Release Blocker

The remaining blocker for public signed distribution is the **Trusted Signing identity validation**,
not the script entrypoints. The account, RBAC role, tooling, and scripts are in place, but a
`PublicTrust` certificate profile cannot be created until the tenant's identity validation is
approved by Microsoft. Once it is approved, create the profile and run the release with
`-UseTrustedSigning`.

This branch does not include:

- a checked-in certificate
- a CI signing secret
- an installer authoring pipeline

The PFX-based path (`sign-windows.ps1`, `BUGNARRATOR_CERT_PATH` / `BUGNARRATOR_CERT_PASSWORD`)
remains available as an alternative; it will fail intentionally rather than produce an unsigned
artifact that looks signed.

## Recommended Next Release Steps

1. Provision a Windows code-signing certificate and store it outside the repo.
2. Add `BUGNARRATOR_WINDOWS_CERT_BASE64` and `BUGNARRATOR_WINDOWS_CERT_PASSWORD` as GitHub repository secrets, or set `BUGNARRATOR_CERT_PATH` and `BUGNARRATOR_CERT_PASSWORD` locally.
3. Produce a signed `Release` package with `windows/scripts/release-windows-tester.ps1`.
4. Validate the signed build on a clean Windows machine.
5. Upload the zip package, signature report, package validation report, and validation notes to GitHub Releases, or use the manual `Windows Tester Release` workflow.

Installer EXE or MSIX packaging should be tracked separately if tester feedback shows that a signed zip is not enough.
