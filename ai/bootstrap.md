# AI Bootstrap

This repo uses a deterministic PR-driven workflow:

- Claude = planning only
- Codex = implementation only
- Review = GitHub PR + CI + Gemini Code Assist on GitHub

The repo is the source of truth for execution state.
GitHub pull requests, CI, and review are the source of truth for acceptance.

## Mandatory startup steps for every run

1. Read this file first.
2. Read `/ai/plan.md`
3. Read `/ai/tasks.md`
4. Read `/ai/acceptance.md`
5. Read `/state/current_task.md`
6. Read `/state/controller.md`
7. Read `/state/implementation_notes.md` if it exists
8. Read `/state/validation_report.md` if it exists

## Role boundaries

### Claude

- May read the repo and plan work
- Must NOT write production code
- Must NOT redesign the whole system unless explicitly asked
- Must produce small, executable task slices

### Codex

- May implement code, tests, and fixes
- Must work only on the current task
- Must NOT re-plan the project
- Must NOT invent new workstreams
- Must treat CI failures and actionable review comments as continuation of the same task
- Must commit only after relevant local preflight passes

### Review

- Happens only through GitHub pull requests, CI, and review comments
- Must NOT require a local Gemini handoff step
- Must drive concrete PASS or FAIL feedback back into repo state

## Global rules

- One repo at a time
- One current task at a time
- No agent-to-agent communication
- Small commits
- No docs-only commits
- No state-only commits
- Docs/state updates allowed only when paired with real code or test changes
- Acceptance is determined by GitHub review state
- Controller file controls handoff status
- CI or PR review failure stays on the same task

## Controller-driven handoff

- `/state/controller.md` is the file-driven handoff source for model-to-model execution.
- Use `/prompts/claude_launcher.txt`, `/prompts/codex_launcher.txt`, and `/prompts/review_launcher.txt` for controller-driven runs.
- If the controller `current_state` does not match your role, do nothing and report that no action is needed.

## Review-ready checklist

- The working branch is pushed or updated
- Relevant local validation has already passed
- A pull request is open or updated
- GitHub CI is running or has run
- GitHub review feedback has been collected

## Review failure rule

If GitHub CI fails OR pull request review, including Gemini Code Assist on GitHub, identifies issues:

- set controller status to `review_failed_fix_required`
- Codex owns the next step
- Codex must fix issues and return to `ready_for_review`

If review reveals a planning or design issue:

- set controller status to `ready_for_claude`

## Review signal rule

Review is considered FAILED if:

- any GitHub check fails
- CI status is not green
- required checks are failing
- pull request review has actionable comments

Review is considered PASSED if:

- all required checks are green
- no blocking review comments remain

## Loop

1. Claude creates or refines plan/tasks/acceptance
2. Claude sets one task in `/state/current_task.md`
3. Codex implements that task and performs local preflight validation
4. Codex sets `ready_for_review`
5. The branch is pushed and the pull request is opened or updated
6. Review happens only through GitHub CI and Gemini Code Assist on GitHub
7. If review finds implementation issues: set `review_failed_fix_required`
8. Codex fixes review issues and returns the repo to `ready_for_review`
9. If review reveals a planning problem: set `ready_for_claude`
10. If review passes: set `done`
