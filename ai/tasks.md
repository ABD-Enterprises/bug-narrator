# Tasks

## Task List

### T1

Title: Run the `RR-002-T4` real Windows validation pass and record the first concrete defect or PASS result.

Files likely in scope:

- `windows/scripts/invoke-windows-codex-handoff.ps1`
- `windows/docs/WINDOWS_VALIDATION_CHECKLIST.md`
- `state/current_task.md`

Done when:

- the scripted Windows baseline has been run from a real Windows machine or VM
- the live tray, recording, screenshot, and hotkey checks are recorded with concrete PASS or FAIL details
- the pull request is ready for GitHub review

Status: pending

---

### T2

Title: Fix the first Windows runtime defect found by `T1` and rerun the relevant validation.

Files likely in scope:

- `windows/src/BugNarrator.Windows/**`
- `windows/src/BugNarrator.Windows.Services/**`
- `windows/tests/BugNarrator.Windows.Tests/**`

Done when:

- one concrete Windows runtime defect from pull request review or CI is fixed
- the relevant local preflight commands are rerun
- the branch is ready for the next review pass

Status: pending
