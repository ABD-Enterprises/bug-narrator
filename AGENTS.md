# Agent Rules

Read `ai/bootstrap.md` first — it is the authoritative workflow entry point.

## Pipeline (deterministic, cron-driven)

```
Planning step (mode-dependent) → writes ai/ → sets ready_for_codex
Execution step → opens PR + queues auto-merge when allowed → sets ready_for_review
CI passes → GitHub merges when repo policy allows it
watch-open-prs → detects merge, advances state to ready_for_codex (next task) or done
```

State flow: `ready_for_codex` → `ready_for_review` → (merge) → `ready_for_codex` | `done`  
Failure: `review_failed_fix_required` → fix → `ready_for_review`  
Legacy replanning escape hatch: `ready_for_claude` → planning owner updates `ai/` → `ready_for_codex`

## Role boundaries

`ai.config.json` declares the repo execution mode:

- `strict` — planning and implementation stay intentionally separated
- `paired` — either Codex or Claude may own planning, but review and merge still happen through PR + CI
- `solo` — one tool may plan and implement in the same lease, but it must still write planning artifacts before code changes, open a PR, and wait for external checks

**Planning owner** — writes `ai/` files, updates `docs/roadmap/state.json` and repo policy config when needed, then sets `ready_for_codex`.
**Execution owner** — implements the current task, runs local validation, opens/updates PR, and handles review remediation by default.
**watch-open-prs** — merges green PRs, advances state automatically. Codex never merges its own PR.  
**No agent-to-agent communication.** Coordination happens only through repo files and PR/CI state.

## State file ownership (critical)

Execution owner writes: `state/current_task.md`, `state/controller.md`, `state/tasks.json`, `state/artifacts.json`, `state/implementation_notes.md`, `state/validation_report.md`, `state/handoff.json`
Planning owner writes: `ai/` files, `docs/roadmap/state.json`, `ai.config.json`
**Always commit state changes immediately** — automated readers use `git show origin/main:<file>` and will not see uncommitted local changes.

## Execution lease

Codex acquires a 90-minute lease before starting work:

- `execution_status: in_progress` + `execution_lease_expires_at` in the future → another instance is running, **STOP**
- `execution_status: in_progress` + lease expired → clear all lease fields, commit `fix: clear stale lease [task_id]`, push, then start
- Always clear the lease (set `execution_status: idle`, blank all lease fields) before setting `ready_for_review`

## Git safety

- Stage specific files only — never `git add -A` or `git add .`
- Never commit directly to `main` — use feature branches and PRs
- Run `git diff --cached --stat` before every commit to verify what is staged
- Never commit secrets, node_modules, __pycache__, .env, or generated artifacts
- Use `--force-with-lease` for own branch pushes only; never force-push `main`

## Validation

GitHub pull requests are the only validation trigger. Never run validation outside of a PR context or bypass CI.

## Before setting ready_for_review

0. Rebase branch onto current main: `git fetch origin main && git rebase origin/main` — prevents DIRTY PR state.
1. All repo-local validation must pass (see `ai/bootstrap.md` for the exact commands)
2. `node tools/validators/enforce-runtime-guardrails.mjs --repo . --config ai.config.json` must pass
3. `state/artifacts.json` must reflect actual evidence (real file paths, correct statuses)
4. Lease must be cleared (`execution_status: idle`)

**If validate.sh passes locally, CI must also pass.** Local and CI validation use the same validator. A CI failure after a local pass means validate.sh is broken — fix it before opening more PRs.

## Batch mode (Codex)

Codex implements **up to 3 sequential tasks per run** on one branch and one PR:

- Lease is acquired **once** at the start and covers the entire batch.
- After each task: commit the work, mark the task `done` in `state/tasks.json`, check elapsed time.
- Branch is named after the **first** task in the batch. PR title lists all completed task IDs.
- If validation fails mid-batch: commit partial work, open PR with what was done, stop (do not attempt the next task).
- `state/current_task.md` `task_id` updates to each task as the batch progresses — this is expected and correct.
- watch-open-prs is batch-aware: it finds the first `pending` task in tasks.json after all batch-completed tasks.

**Do not stop after the first task** — continue the batch loop until: 3 tasks done, 75 min elapsed, or no more pending tasks.

## Scope rules

- Work on the current task only — do not change files outside the declared scope in `ai/tasks.md`
- Planning artifacts may be updated only to plan the active task before code changes begin
- Document any necessary out-of-scope changes in `state/implementation_notes.md`
- If the task is ambiguous or blocked: set `ready_for_claude` only when the repo still uses that legacy replanning lane; otherwise update planning artifacts, document reason, clear lease, and stop

## artifacts.json contract (validator-enforced — violations fail CI)

Valid `status` + `paths` combinations for each evidence type (`build`, `test`, `run`, `deploy`):

| status | paths | metadata_only | When to use |
|--------|-------|---------------|-------------|
| `"passed"` | non-empty array | false (omit) | Evidence captured; artifact files exist at listed paths |
| `"not_run"` | `[]` (empty) | `true` | Evidence cannot be captured in CI (macOS-only build, local-only lint, etc.) |
| `"not_required"` | `[]` (empty) | omit | This evidence type does not apply (e.g., deploy for a library) |
| `"blocked"` | `[]` (empty) | omit | Blocked by a known upstream dependency |

**Invalid combinations that WILL fail CI:**
- `"status": "passed"` + empty `paths[]` → FAIL (passed requires artifacts)
- `"status": "passed"` + `"metadata_only": true` → FAIL (double violation)
- `"status": "not_run"` + `"metadata_only": true` + type NOT in `allowed_metadata_only_evidence_types` → FAIL
- evidence paths that point at generated output trees like `dist/`, `build/`, `.next/`, `coverage/`, or `node_modules/` → FAIL

**`code_changes_present`**: Set to `true` if any production code changed. Set to `false` only for state-only or docs-only commits.

**Always run the validator BEFORE writing artifacts.json.** Never pre-populate artifacts.json with CI tracking fields — the validator writes those. If `scripts/validate.sh` writes artifacts.json before calling the validator, that is a bug.

## Validator integrity (enterprise standard — do not modify)

`tools/validators/enforce-runtime-guardrails.mjs` is synced from enterprise-ai-standards and must not be modified in this repo. The file is hash-verified by CI before execution. Modifications will cause CI to fail immediately with an integrity error.

To update the validator: submit a change to enterprise-ai-standards and run the sync script.

## Repo-specific rules

his file configures AI coding agents (Codex, etc.) for the BugNarrator repo.

## What This Repo Is

BugNarrator is a desktop tool for narrated software testing sessions. It records audio, captures screenshots, transcribes via OpenAI, extracts issues with AI, and exports session bundles. The core workflow is `record -> review -> refine -> export`.

- **macOS app**: Swift 6.0 / SwiftUI / AppKit, menu bar app, macOS 14+
- **Windows app**: C# / .NET 8 / WPF, system tray app (in progress)
- **Current version**: 1.0.22 (macOS production, Windows in development)

## OS Detection

This is a dual-platform project. **Check which OS you're running on before doing any work.** The platforms have completely separate toolchains and codebases.

### If Running on macOS

You can work on:
- The Swift/SwiftUI macOS app in `Sources/BugNarrator/`
- macOS tests in `Tests/BugNarratorTests/`
- Build scripts in `scripts/`
- Documentation in `docs/` and `site/`
- CI workflow files in `.github/workflows/`

Build and test commands:
```bash
xcodegen generate  # only if project.yml changed
xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO build
xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO test
./scripts/release_smoke_test.sh
./scripts/accessibility_regression_check.sh
```

You CANNOT:
- Build, test, or validate the Windows .NET workspace
- Run PowerShell build scripts
- Validate Windows package artifacts

### If Running on Windows

You can work on:
- The C#/.NET 8 Windows app in `windows/src/`
- Windows tests in `windows/tests/`
- Windows build/package scripts in `windows/scripts/`
- Documentation in `docs/` and `site/`
- CI workflow files in `.github/workflows/`
- Platform-neutral models in `windows/src/BugNarrator.Core/`

Build and test commands:
```powershell
./windows/scripts/build-windows.ps1 -Configuration Debug
./windows/scripts/test-windows.ps1 -Configuration Debug
./windows/scripts/package-windows.ps1 -Configuration Release
./windows/scripts/validate-windows-package.ps1 -Runtime win-x64
```

You CANNOT:
- Build, test, or validate the macOS Swift app
- Run xcodebuild, xcodegen, or any Xcode tooling
- Validate DMG packaging, code signing, or notarization
- Run the macOS accessibility regression script

### Either OS

You can always work on:
- Markdown documentation in `docs/`
- Docusaurus site content in `site/` (requires Node 22)
- CI workflow YAML in `.github/workflows/`
- Roadmap state in `docs/roadmap/`
- Parity matrix in `docs/architecture/parity-matrix.md`

## Key Source of Truth Documents

- **Product spec**: `docs/architecture/product-spec.md`
- **Roadmap state**: `docs/roadmap/state.json`
- **Parity matrix**: `docs/architecture/parity-matrix.md`
- **OS-aware roadmap**: `docs/roadmap/codex-roadmap.md`
- **Changelog**: `CHANGELOG.md`
- **Windows implementation plan**: `windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md`

## Current Phase

`RR-002 Windows Runtime Validation And Hardening` — validate WPF tray shell, recording lifecycle, screenshot capture, and hotkey registration on real Windows. CI scaffolding is done; real desktop validation is the gap.

## Open Bugs

- **BN-P1-014** (macOS): Exported session bundles can omit screenshots that the transcript references. Suspected area: `SessionBundleExportService` copies only files still on disk at export time.

## Architecture

### macOS (Sources/BugNarrator/)
- `Models/` — data models (sessions, issues, transcripts)
- `Services/` — 22 service files (recording, permissions, export, transcription, etc.)
- `Views/` — SwiftUI views
- `Utilities/` — session library, single-instance, diagnostics
- `AppState.swift` — central state orchestration
- `BugNarratorApp.swift` — app entry point

### Windows (windows/src/)
- `BugNarrator.Core/` — platform-neutral models (shared)
- `BugNarrator.Windows/` — WPF UI shell, tray integration, view models
- `BugNarrator.Windows.Services/` — Windows-specific services (audio, screenshots, hotkeys, secrets)

## CI Pipeline

| Job | Runner | Trigger |
| --- | --- | --- |
| `docs-site-validation` | ubuntu-latest | push + PRs |
| `windows-workspace-validation` | windows-latest | push + PRs |
| `package-macos` (release only) | macos-15 | manual workflow_dispatch |

No macOS CI job runs on PRs. macOS validation is release-time only.

## Rules

- Do not modify `docs/architecture/product-spec.md` without explicit instruction
- Do not bump the version in `project.yml` or CHANGELOG without explicit instruction
- Do not create or modify release artifacts without explicit instruction
- Always run tests after code changes
- Keep the parity matrix updated when Windows features change
- Update `docs/roadmap/state.json` when completing or starting phases
