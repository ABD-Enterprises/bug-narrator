# AI Bootstrap

This repo uses a three-role workflow:

- Claude = planning only
- Codex = implementation only
- Review = GitHub PR + CI + Gemini Code Assist on GitHub

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

- May implement code and tests
- Must work only on the current task
- Must NOT re-plan the project
- Must NOT invent new workstreams
- Must run validation relevant to the task
- Must commit only after validation passes

### Review

- Must validate through GitHub pull request review and CI
- Must NOT redesign the feature
- Must NOT broaden scope
- Must drive concrete PASS or FAIL feedback back into the repo state

## Global rules

- One repo at a time
- One current task at a time
- Small commits
- No docs-only commits
- No state-only commits
- Docs/state updates allowed only when paired with real code or test changes
- Acceptance criteria control completion
- Validation report controls rework
- Controller file controls handoff status

## Controller-driven handoff

- `/state/controller.md` is the file-driven handoff source for model-to-model execution.
- Use `/prompts/claude_launcher.txt`, `/prompts/codex_launcher.txt`, and `/prompts/review_launcher.txt` for controller-driven runs.
- If the controller status does not match your role, do nothing and report that no action is needed.

## Review-ready checklist

- The working branch is pushed or updated
- Relevant local validation has already passed
- A pull request is open or updated
- GitHub CI is running or has run
- GitHub review feedback has been collected

## Loop

1. Claude creates or refines plan/tasks/acceptance
2. Set one task in `/state/current_task.md`
3. Codex implements that task and performs local validation
4. Codex moves the repo to `ready_for_review`
5. The branch is pushed and the pull request is opened or updated
6. Review happens through GitHub CI and Gemini Code Assist on GitHub
7. If review finds implementation issues: set `review_failed_fix_required`
8. Codex fixes review issues and returns the repo to `ready_for_review`
9. If review reveals a planning problem: set `ready_for_claude`
10. If review passes: set `done`
