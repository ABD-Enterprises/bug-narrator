# Mega Execution Prompt

Read `/ai/bootstrap.md` first.
It is the authoritative entry point for AI-assisted work in this repo.
Use this file only as a supplemental execution template that does not override bootstrap.
For controller-driven multi-model runs, use the appropriate launcher prompt and follow `/state/controller.md`.

1. Load `docs/roadmap/state.json` and every required `/state/*.json` file.
2. Review branch, worktree, last commit, unresolved risks, and current opportunities.
3. Respect `current_phase`, `phase_type`, `phase_status`, and `active_task_id` from `docs/roadmap/state.json` instead of inventing a parallel plan.
4. Execute real code, config, workflow, or validation work.
5. Run the relevant commands and record file-backed evidence in `state/artifacts.json` with `passed`, `failed`, `not_run`, `blocked`, or `not_required`.
6. Update `docs/roadmap/state.json`, `state/tasks.json`, `state/risks.json`, `state/decisions.json`, `state/artifacts.json`, and `state/handoff.json` whenever progress, evidence, risks, or decisions change.
7. Run `./scripts/validate.sh`.
8. Do not claim completion, merge, or deployment without evidence.
