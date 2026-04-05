# GitHub Review Supplemental Guidance

- Read `/ai/bootstrap.md` first.
- It is the authoritative entry point for AI-assisted work in this repo.
- Review here means GitHub CI, pull request review, and Gemini Code Assist on GitHub if configured.
- This file is the repo-specific supplement for the review stage.
- Follow `/state/controller.md` for handoff status; if it is not the review stage, do nothing.
- When review finds implementation issues, drive the controller to `review_failed_fix_required` instead of bypassing the Codex remediation pass.
- Review against the canonical execution and roadmap state, not chat-only context.
- Prioritize missing evidence, stale or missing state updates, silently dropped unresolved risks, and phase-completion claims without proof.
- Treat `tools/validators/enforce-runtime-guardrails.js` as the enforcement source of truth for repo execution guardrails.
- Require file-backed evidence in `state/artifacts.json` for build, test, run, validation, or deploy claims, and flag any claim that lacks a recorded result.
- If GitHub review automation is configured, `.gemini/config.yaml` and `/gemini` PR comments are the integration surface.
