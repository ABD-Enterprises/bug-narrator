# Windows Codex Handoff

This document is the Windows takeover entrypoint for Codex.

Use it when a Codex instance is running on a real Windows machine or VM and needs to continue the current Windows phase without reconstructing repo state by hand.

## Current Takeover Target

As of 2026-04-05:

- active phase: `RR-002 Windows Runtime Validation And Hardening`
- phase type: `build`
- required branch: `phase/bootstrap`
- remaining phase blocker: `RR-002-T4 Run tray, recording, screenshot, and hotkey validation on a real Windows machine or VM`
- unresolved phase risks:
  - `RISK-WIN-001`
  - `RISK-WIN-002`

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
- [Task State](../../state/tasks.json)
- [Risk State](../../state/risks.json)
- [Decision State](../../state/decisions.json)
- [Artifact State](../../state/artifacts.json)
- [Handoff State](../../state/handoff.json)
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

2. Execute the real desktop validation that macOS CI cannot cover:
   - tray icon and single-instance behavior
   - recording lifecycle against a real microphone state
   - screenshot overlay and region capture behavior
   - global hotkey behavior against real desktop apps, reserved shortcuts, and alternate layouts

3. Use [WINDOWS_VALIDATION_CHECKLIST.md](WINDOWS_VALIDATION_CHECKLIST.md) as the runtime checklist for `RR-002-T4`.

4. When real Windows findings land, update:
   - `docs/roadmap/state.json`
   - `state/tasks.json`
   - `state/risks.json`
   - `state/decisions.json`
   - `state/artifacts.json`
   - `state/handoff.json`
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
