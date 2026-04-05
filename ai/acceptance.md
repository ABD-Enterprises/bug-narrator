# Acceptance Criteria

## Global acceptance rules

- GitHub PR review is the source of truth for acceptance
- Required GitHub checks pass
- No unrelated file churn
- No docs-only or state-only commit
- Changes stay within current task scope unless required for the fix
- CI or review failure continues the same task through `review_failed_fix_required`

## Review-ready checklist

- The working branch is pushed or ready to push
- A pull request is open or ready to update
- Relevant local preflight validation already passed
- GitHub CI is running or has run
- GitHub review feedback is collected, including Gemini Code Assist on GitHub if configured
- Review remediation, if needed, is tracked through `review_failed_fix_required`

## Per-task acceptance

### T1

- the Windows baseline command completes on a real Windows machine or VM
- the review handoff can proceed through GitHub PR and CI
- any resulting CI or review failure keeps the task in the implementation loop instead of resetting it

Validation commands:

- `powershell -ExecutionPolicy Bypass -File windows/scripts/invoke-windows-codex-handoff.ps1 -RunBaseline`
- `dotnet run --project windows/src/BugNarrator.Windows/BugNarrator.Windows.csproj -c Debug`

### T2

- the reported defect is no longer reproducible
- the related Windows regression coverage or manual validation has been rerun
- the follow-up review feedback can be collected through GitHub PR and CI
- only a planning or design failure routes the task back to Claude

Validation commands:

- `powershell -ExecutionPolicy Bypass -File windows/scripts/test-windows.ps1 -Configuration Debug`
- `powershell -ExecutionPolicy Bypass -File windows/scripts/validate-windows-package.ps1 -Runtime win-x64`
