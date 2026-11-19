# Handover — sureforge-capture, session ending 2026-11-18

Repository: `SureForgeTech/sureforge-capture` (public). Workspace checkout: `/workspace/sureforge-capture`
at `01c076d15b6695aab15086ebd685579c0bc63c9d` (origin/main), tree clean. Dependencies already
installed for a fast start: `local-transcription/venv` (Python, `parakeet-mlx` excluded as Apple-only,
exactly as CI does) and `site/node_modules` (`npm ci` via `scripts/site_npm.sh ci`).

## Landed on main

| PR | Commit | Issue closed | Merged by |
|---|---|---|---|
| #1354 corrupt-audio fixture prepared before the finalization timer starts | `668ce5f` | #1353 | this session |
| #1368 Windows Ctrl+C-ignore flag normalised in the test host | `faa6192` | #1366 | this session |
| #1365 Session Library navigation/actions reachable in smaller windows; product-name alignment | `da40c3a` | #1363 | this session |
| #1382 version contract enforced by the validation gate | `01c076d` | #1276 | the owner |
| #1383 gate hardening: nesting bounded, released heading pinned | `2c05bb6` | — | the owner |

Each landed with an independent fresh-context review on its exact head, required checks green, squash-only
merge (the org ruleset "Public repositories: changes to main through pull requests" allows `squash` only,
and as of this session requires **0** approving reviews — it previously required 1).

No pull requests are open; `main` is `2c05bb64052f962020dc12e59c40c284a9039820`.

**One thing to know about #1383:** the owner merged it at head `e55f07b`, which had been fixed but **not
independently reviewed** — the review of its predecessor `5d8908f` found one P1 (the watchdog signalled one
process group, so deeper nesting levels survived and kept cloning), a P2 (a committed machine-local
symlink) and documentation overstatements, and the fixes for those were verified locally but not reviewed.
The state of the pull request said so before it was merged. The merged content is the intended one: the
descendant walk is in place, the symlink is gone, and the comments and changelog no longer claim more than
the code does.

What that gate does, and what it does not: it enforces that `VERSION`, `project.yml`'s
`MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` and the latest released heading in `CHANGELOG-archive.md`
agree, on every validation run; it proves by running that the check still catches drift; and it proves by
cloning the repository that a genuine drift fails the validation. Its remaining limits are stated in its own
comments: a committed change that prints the version gate's failure line, or that rewrites the depth marker,
can still defeat the proof — those are committed changes, visible in review, and the independent review of
that change is what catches them.

## Reviewer routes

Kimi's provider allowance is exhausted (all six variants). MiniMax M3 (`minimax-coding-plan/MiniMax-M3`)
works and was used for the later reviews; the same model in a fresh context counts as independent. OpenCode
Go models need an authenticated key this sandbox does not have (the `opencode` provider is configured with
`apiKey: public`, which serves only the free models, and those are rate-limited).

## Remaining board candidates (all admissible: no `ai/blocked`, no PR, no in-development label)

- **#1282** — the version bump script runs on a dirty tree and writes files in place. Prepared owner branch
  `fix/guard-the-version-bump`; pure shell, fully verifiable here.
- **#1281** — the fast Swift parse gate does not parse the test sources. Prepared branch
  `fix/parse-the-tests-too-in-the-fast-gate`; note CI's `runtime-guardrails` installs no Swift toolchain, so
  this gate is inert in CI and only affects developer and cloud machines.
- **#1286** — the Windows diagnostics redactor destroys prose after the word "Basic" (macOS is already
  fixed). Needs .NET, so CI-only verification.
- **#1293** — the shared plaintext-endpoint tables can be weakened by deleting rows. Security-contract gap;
  the fixtures are already checked by a locally runnable Python gate, so this is verifiable here.
- **#1290**, **#1291**, **#1277** — classifier comment accuracy, the unpinned single-render decision, and
  the dead review tab model. Swift or .NET, so CI-only verification.

## Notes for whoever picks this up

- The org ruleset changed mid-session: `required_approving_review_count` is now 0, so a PR can be merged
  without an approval from another account. `dismiss_stale_reviews_on_push` and
  `required_review_thread_resolution` are still on, and `squash` is still the only allowed method.
- `scripts/validate.sh` is the declared validation and CI's `runtime-guardrails` entry point. Run it with
  `VALIDATE_SKIP_BOARD_AUDIT=1` (CI does the same).
- The Windows and macOS test suites cannot run in this Linux sandbox (no `dotnet`, no Swift toolchain); the
  Swift parse check and the Xcode suite report `NOT RUN` here, and CI's `macos-26` and `windows-latest` jobs
  are the real evidence for Windows and macOS changes.
- Never commit `local-transcription/venv` or `site/node_modules`; they are gitignored and must stay that way.
  An earlier commit in this session accidentally tracked a symlink to a machine-local path and it was removed.
