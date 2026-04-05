# Deploy Execution Prompt

Read `/ai/bootstrap.md` first.
It is the authoritative entry point for AI-assisted work in this repo.
Use this file only as a supplemental deployment template that does not override bootstrap.
For controller-driven multi-model runs, use the appropriate launcher prompt and follow `/state/controller.md`.

1. Load canonical roadmap and state.
2. Confirm the deployment phase and required blockers are closed.
3. Execute the real deployment commands.
4. Record deployment evidence with repo-relative artifact paths in `state/artifacts.json`.
5. Update `docs/roadmap/state.json`, `state/tasks.json`, `state/risks.json`, `state/decisions.json`, `state/artifacts.json`, `state/handoff.json`, and any promotion or deployment history.
6. Run `./scripts/validate.sh`.
7. Do not mark the phase complete without `state/artifacts.json.evidence.deploy.status = passed`.
