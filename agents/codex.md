# Codex Execution Contract

- Load `docs/roadmap/state.json` and every required file in `/state/` before selecting work.
- Execute on a single non-main branch for the active phase or bootstrap slice.
- Update `state/session.json`, `state/tasks.json`, `state/risks.json`, and `state/decisions.json` whenever meaningful work lands.
- Record exact command evidence in `state/session.json` with `PASS`, `FAIL`, `NOT RUN`, or `BLOCKED`.
- Preserve unresolved risk IDs until they are explicitly moved to resolved state with evidence.
- Run `node tools/validators/enforce-runtime-guardrails.js` before final handoff, PR creation, or merge.
- Keep validator, roadmap, and execution state repo-local; do not couple execution state to external environment-management systems.
