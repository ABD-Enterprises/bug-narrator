# Acceptance Criteria

## Global acceptance rules

- Build passes
- Relevant tests pass
- No unrelated file churn
- No docs-only or state-only commit
- Changes stay within current task scope unless required for the fix
- The live validation result is captured as PASS or FAIL in `/state/validation_report.md`

## Review-ready checklist

- The working branch is pushed or ready to push
- A pull request is open or ready to update
- Relevant local validation already passed
- GitHub CI is running or has run
- GitHub review feedback is collected, including Gemini Code Assist on GitHub if configured
- Review remediation, if needed, is tracked through `review_failed_fix_required`

## Per-task acceptance

### T1

- the Windows baseline command completes on a real Windows machine or VM
- the review handoff can proceed through GitHub PR and CI with concrete PASS or FAIL details recorded in `/state/validation_report.md`

Validation commands:

- `powershell -ExecutionPolicy Bypass -File windows/scripts/invoke-windows-codex-handoff.ps1 -RunBaseline`
- `dotnet run --project windows/src/BugNarrator.Windows/BugNarrator.Windows.csproj -c Debug`

### T2

- the reported defect is no longer reproducible
- the related Windows regression coverage or manual validation has been rerun
- the follow-up review feedback can be collected through GitHub PR and CI

Validation commands:

- `powershell -ExecutionPolicy Bypass -File windows/scripts/test-windows.ps1 -Configuration Debug`
- `powershell -ExecutionPolicy Bypass -File windows/scripts/validate-windows-package.ps1 -Runtime win-x64`
