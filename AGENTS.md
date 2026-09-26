# Local AI Adapter (Codex)

## Repo-Specific Effort Leak Guardrails

- Before starting implementation, run `gh issue list --repo ABD-Enterprises/bug-narrator --state open --limit 200` or `scripts/effort-leak-audit.sh` when GitHub auth is available.
- Do not implement an issue that is already closed, has an open PR, or is labeled `ai/blocked` unless the blocker has been removed and documented in the issue.
- If an issue is blocked by an external credential, signing certificate, account permission, hardware, or clean-machine validation, comment with the exact missing input and keep it in `ai/blocked`; do not create placeholder repo churn.
- Prefer one small PR per issue. If replacing stale work, close or comment on the superseded PR with `superseded-by: #<new-pr>` before spending CI on a new branch.
- Run `scripts/effort-leak-audit.sh` before pushing batches that touch GitHub workflow, issue, PR, or release automation.
