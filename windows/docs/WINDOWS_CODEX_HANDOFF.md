# Windows Codex Handoff

This document is the Windows takeover entrypoint for Codex.

Use it when a Codex instance is running on a real Windows machine or VM and needs to continue the current Windows phase without reconstructing repo state by hand.

## Current Takeover Target

As of 2026-04-04:

- active phase: `RR-002 Windows Runtime Validation And Hardening`
- required branch: `phase/RR-002-windows-runtime-hardening`
- completed phase blocker: `RR-002-T4 Run tray, recording, screenshot, and hotkey validation on a real Windows machine or VM`
- unresolved phase risks:
  - `RISK-WIN-002`
- related follow-up risk outside this phase:
  - `RISK-CI-002 -> OPS-011`
- real Windows evidence captured on this branch:
  - tray icon found in the system-tray overflow
  - duplicate launch focused the primary instance
  - microphone-backed recording completed successfully
  - screenshot overlay region capture persisted deterministic artifacts
  - out-of-focus hotkeys worked from Notepad focus
  - reserved shortcut rejection was observed for `Shift+Win+S`
  - retry-needed sessions remained recoverable without an OpenAI key
  - debug-bundle export succeeded from the review flow
  - live GitHub export succeeded through the production Windows service path using a disposable private repository
  - production-path session deletion removed the saved session directory cleanly
  - corrupted screenshot-path metadata was excluded safely from the loaded session and the exported session bundle
- remaining validation gaps from the April 4, 2026 passes:
  - live OpenAI validation with a real API key
  - live Jira export validation with real credentials
  - alternate keyboard layout behavior on a machine with more than one installed input layout
  - multi-monitor or mixed-DPI proof on a suitable Windows machine
  - signed public-release proof after installer and signing prerequisites are available

## First Command On Windows

From the repo root, run:

```powershell
powershell -ExecutionPolicy Bypass -File windows/scripts/invoke-windows-codex-handoff.ps1 -RunBaseline
```

That script:

- reads the current roadmap and state files
- records the current branch, head commit, tasks, risks, and opportunities
- runs the current scripted Windows baseline:
  - `build-windows.ps1`
  - `test-windows.ps1`
  - `package-windows.ps1`
  - `validate-windows-package.ps1`
- writes a machine-readable handoff report to:

```text
windows/artifacts/handoff/windows-codex-handoff.json
```

## Required Source Of Truth

Load these before making Windows changes:

- [Canonical Product Spec](../../docs/architecture/product-spec.md)
- [Roadmap State](../../docs/roadmap/state.json)
- [Session State](../../state/session.json)
- [Task State](../../state/tasks.json)
- [Risk State](../../state/risks.json)
- [Windows README](../README.md)
- [Windows Implementation Roadmap](WINDOWS_IMPLEMENTATION_ROADMAP.md)
- [Windows Validation Checklist](WINDOWS_VALIDATION_CHECKLIST.md)
- [Cross-Platform Guidelines](../../docs/CROSS_PLATFORM_GUIDELINES.md)

## What Windows Codex Should Do Next

After the baseline passes on Windows:

1. Launch the app with:

```powershell
dotnet run --project windows/src/BugNarrator.Windows/BugNarrator.Windows.csproj -c Debug
```

2. If the tray, recording, screenshot, or hotkey surfaces change again, rerun the real desktop validation that macOS CI cannot cover:
   - tray icon and single-instance behavior
   - recording lifecycle against a real microphone state
   - screenshot overlay and region capture behavior
   - global hotkey behavior against real desktop apps, reserved shortcuts, and alternate layouts

3. Use [WINDOWS_VALIDATION_CHECKLIST.md](WINDOWS_VALIDATION_CHECKLIST.md) as the runtime checklist for any rerun and preserve the April 4, 2026 evidence-backed gaps unless you materially expand the real Windows coverage.

4. The next honest WIN-010 blockers are now narrower:
  - OpenAI transcription, summary, and issue extraction with a real key
  - Jira export with real credentials
  - alternate keyboard layout validation
  - mixed-display validation
  - signed public-release proof through WIN-011

5. When new real Windows findings land, update:
  - `docs/roadmap/state.json`
  - `state/session.json`
  - `state/tasks.json`
  - `state/risks.json`
   - `state/decisions.json`
   - `windows/README.md`
   - `windows/docs/WINDOWS_VALIDATION_CHECKLIST.md`

## Expected Artifacts

After a successful scripted baseline, these files should exist:

- `windows/artifacts/packages/BugNarrator-windows-win-x64.zip`
- `windows/artifacts/validation/BugNarrator-windows-win-x64-validation.json`
- `windows/artifacts/publish/win-x64/bugnarrator-smoke-report.json`
- `windows/artifacts/handoff/windows-codex-handoff.json`

The current CI run on this branch also uploads these artifacts from `windows-latest`:

- `bugnarrator-windows-package`
- `bugnarrator-windows-validation`
- `bugnarrator-windows-handoff`

## Scope Guardrails

- Do not close `RISK-WIN-001` or `RISK-WIN-002` until the real Windows runtime checklist has been executed.
- Do not claim tray, overlay, capture, hotkey, or credential-provider behavior from macOS-only or CI-only evidence.
- Keep all RR-002 work on `phase/RR-002-windows-runtime-hardening`.
