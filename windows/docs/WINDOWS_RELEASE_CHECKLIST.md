# BugNarrator Windows Release Checklist

## Phase A: Trusted Tester Zip

- run `windows/scripts/build-windows.ps1`
- run `windows/scripts/test-windows.ps1`
- run `windows/scripts/package-windows.ps1`
- run `windows/scripts/validate-windows-package.ps1`
- confirm `windows/artifacts/packages/BugNarrator-windows-win-x64.zip` exists
- confirm the packaged smoke report exists and passed
- note that the artifact is unsigned unless certificate-based signing has been completed separately

## Phase B: Public Release Candidate

- run `windows/scripts/release-windows-phase-b.ps1`
- confirm `windows/artifacts/releases/public/<label>/public-release-status.json` exists
- if status is `blocked`, do not publish a public Windows release
- if status is `ready`, confirm:
  - the signed installer exists
  - the trusted-tester zip still exists for internal use
  - checksums were generated
  - the release notes and public guidance are current

## Required Public Release Prerequisites

- Inno Setup 6 installed or available through `-InstallerCompilerPath`
- `signtool.exe` available on `PATH` or passed explicitly
- `BUGNARRATOR_CERT_PATH` set to a real code-signing certificate outside the repo
- `BUGNARRATOR_CERT_PASSWORD` set for the current shell session

## Clean-Machine Validation

- install the public installer on a clean Windows machine or VM
- confirm the tray app launches without requiring a separate .NET installation
- open Recording Controls and confirm `Start Recording`, `Stop Recording`, `Capture Screenshot`, `Open Session Library`, and `Close`
- validate a short recording session end to end
- confirm Session Library opens and preserves the session
- uninstall BugNarrator and confirm the installed app is removed cleanly
- reinstall or upgrade and confirm `%LocalAppData%\\BugNarrator\\` data survives when intended

## Signing Validation

- verify the installed executable signature with `Get-AuthenticodeSignature`
- verify the installer signature with `Get-AuthenticodeSignature`
- confirm any timestamping step completed successfully
- do not label a Windows artifact as public-ready unless installer and app signatures are present
