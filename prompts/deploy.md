# Deploy Execution Prompt

1. Load canonical roadmap and state.
2. Confirm the deployment phase and required blockers are closed.
3. Execute the real deployment commands.
4. Record deployment evidence with exact commands and artifact or environment results.
5. Update roadmap and execution state, including any promotion or deployment history.
6. Run `node tools/validators/enforce-runtime-guardrails.js`.
7. Do not mark the phase complete without `deploy` evidence recorded as `PASS`.
