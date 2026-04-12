# Controller State

current_state: ready_for_codex
state_owner: Claude

## allowed_transitions

- ready_for_claude -> ready_for_codex
- ready_for_claude -> blocked
- ready_for_codex -> ready_for_review
- ready_for_codex -> blocked
- ready_for_review -> review_failed_fix_required
- ready_for_review -> ready_for_claude
- ready_for_review -> done
- ready_for_review -> blocked
- review_failed_fix_required -> ready_for_review
- review_failed_fix_required -> ready_for_claude
- review_failed_fix_required -> blocked

## transition_rules

- ready_for_claude -> ready_for_codex: Claude has updated `/ai/plan.md`, `/ai/tasks.md`, `/ai/acceptance.md`, and `/state/current_task.md` for one task slice.
- ready_for_claude -> blocked: Planning cannot continue without external intervention or missing context that the repo cannot supply.
- ready_for_codex -> ready_for_review: Codex has implemented the current task, completed local preflight checks, and prepared the branch for PR review.
- ready_for_codex -> blocked: Codex cannot continue implementation without external intervention.
- ready_for_review -> review_failed_fix_required: Any GitHub check fails, required CI is not green, or actionable pull request review comments remain.
- ready_for_review -> ready_for_claude: Review exposes a planning_failure or design issue that cannot be solved inside the current task scope.
- ready_for_review -> done: All required GitHub checks are green and no blocking review comments remain.
- ready_for_review -> blocked: GitHub review cannot proceed because the branch, PR, or review infrastructure is unavailable.
- review_failed_fix_required -> ready_for_review: Codex has fixed the same task, rerun local preflight checks, and pushed the branch for another PR review pass.
- review_failed_fix_required -> ready_for_claude: Codex determines the failure is actually a planning_failure that requires replanning.
- review_failed_fix_required -> blocked: Codex cannot fix the CI or review failure without external intervention.

## done_criteria

- The active pull request has no blocking review comments
- All required GitHub checks are green
- `/state/current_task.md` reflects a completed review pass
- The current task can advance without another Codex fix pass

## blocked_criteria

- The task cannot continue without external intervention
- Required GitHub access, platform access, or credentials are unavailable
- The next valid transition cannot be executed from repo state and PR state alone
