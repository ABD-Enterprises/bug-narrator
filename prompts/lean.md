# Lean Execution Prompt

Read `/ai/bootstrap.md` first.
It is the authoritative entry point for AI-assisted work in this repo.
Use this file only as a supplemental execution template that does not override bootstrap.
For controller-driven multi-model runs, use the appropriate launcher prompt and follow `/state/controller.md`.

Load canonical roadmap and state, execute the smallest real change that advances the active phase, record file-backed evidence in `state/artifacts.json`, update `docs/roadmap/state.json`, `state/tasks.json`, `state/risks.json`, `state/decisions.json`, and `state/handoff.json` if anything changed, and finish by running `./scripts/validate.sh`.
