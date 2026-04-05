# Codex Supplemental Guidance

- Read `/ai/bootstrap.md` first.
- It is the authoritative entry point for AI-assisted work in this repo.
- Codex's role here is implementation only.
- Use this file only for repo-specific implementation guidance that does not override bootstrap.
- Follow `/state/controller.md` for handoff status; if it is not Codex's turn, do nothing.
- Load `docs/roadmap/state.json` and every required file in `/state/` before selecting work.
- Execute on a single non-main branch for the active phase or bootstrap slice.
- Update `state/tasks.json`, `state/risks.json`, `state/decisions.json`, `state/artifacts.json`, and `state/handoff.json` whenever meaningful work lands.
- Record file-backed evidence in `state/artifacts.json` with `passed`, `failed`, `not_run`, `blocked`, or `not_required`.
- Preserve unresolved risk IDs until they are explicitly moved to resolved state with evidence.
- Run `./scripts/validate.sh` before final handoff, PR creation, or merge.
- Keep validator, roadmap, and execution state repo-local; do not couple execution state to external environment-management systems.
