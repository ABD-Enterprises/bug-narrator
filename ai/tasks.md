# Tasks

## Task List

### T1

Title: Align PR #5 branch state and validation evidence with the latest runtime guardrails contract.

Files likely in scope:

- `ai/tasks.md`
- `ai/acceptance.md`
- `state/artifacts.json`
- `state/controller.md`
- `state/current_task.md`
- `state/handoff.json`
- `state/repo.json`
- `state/tasks.json`
- `artifacts/pr-driven-workflow/*`

Done when:

- the branch-local execution state reflects PR #5 instead of the old `phase/bootstrap` task
- `./scripts/validate.sh 9a0048fc6397f1be3086b3753b2afa4a912399d2` passes
- targeted `SettingsStore` validation already has passing evidence on the branch
- the pull request is ready for GitHub review

Status: completed

---

### T2

Title: Fix any follow-up PR #5 CI or review failures without reopening planning.

Files likely in scope:

- `Sources/BugNarrator/**`
- `Tests/BugNarratorTests/**`
- `state/**`

Done when:

- one concrete PR failure from GitHub review or CI is fixed
- the relevant local preflight commands are rerun
- the branch is ready for the next review pass

Status: pending
