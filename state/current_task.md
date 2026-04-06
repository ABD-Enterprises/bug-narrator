# Current Task

task_id: T1
description: Run the `RR-002-T4` real Windows validation pass and record the first concrete PASS or FAIL result.
branch: phase/bootstrap
pr_link: none
owner: Claude
current_state: blocked
failure_type: none
acceptance_criteria_reference: /ai/acceptance.md#t1
last_action: Claude reviewed T1. Task requires running on a real Windows machine or VM — not executable by Codex in a Linux sandbox.
next_action: Human must run `windows/scripts/invoke-windows-codex-handoff.ps1` on a Windows machine, record results in WINDOWS_VALIDATION_CHECKLIST.md, open a PR, and then set controller to ready_for_review.
