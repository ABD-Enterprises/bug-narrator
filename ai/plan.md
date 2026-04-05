# Plan

## Goal

Advance the active roadmap task through one pull-request-scoped slice at a time.

## Execution model

- Claude plans only.
- Codex implements and fixes only.
- GitHub PR review and CI accept or reject work.

## Constraints

- Keep scope narrow
- Prefer local changes
- No unnecessary architecture work
- Preserve existing behavior unless explicitly changing it
- Do not reset the task when CI or review fails

## Approach

1. Break work into small task slices.
2. Encode the active slice in `/state/current_task.md`.
3. Each slice should be completable in one Codex implementation pass plus zero or more fix passes.
4. Validation is determined by GitHub PR review and CI.
