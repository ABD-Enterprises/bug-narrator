# Handover — sureforge-capture, session ending 2026-11-19

(This file continues the 2026-11-18 handover in place: the path is a standing reference, so the
name was left as it was and the content is updated to the end of the 2026-11-19 session.)

Repository: `SureForgeTech/sureforge-capture` (public). Workspace checkout: `/workspace/sureforge-capture`
on branch `fix/1286-windows-basic-redaction` at `f234e0a` (a merged branch); `origin/main` is at
`9fb630fbcef4`. Dependencies already installed for a fast start: `local-transcription/venv` (Python,
`parakeet-mlx` excluded as Apple-only, exactly as CI does) and `site/node_modules` (`npm ci` via
`scripts/site_npm.sh ci`).

## Landed on main

| PR | Commit | Issue closed | Merged by |
|---|---|---|---|
| #1354 corrupt-audio fixture prepared before the finalization timer starts | `668ce5f` | #1353 | this session |
| #1368 Windows Ctrl+C-ignore flag normalised in the test host | `faa6192` | #1366 | this session |
| #1365 Session Library navigation/actions reachable in smaller windows; product-name alignment | `da40c3a` | #1363 | this session |
| #1382 version contract enforced by the validation gate | `01c076d` | #1276 | the owner |
| #1383 gate hardening: nesting bounded, released heading pinned | `2c05bb6` | — | the owner |
| #1384 version bump refuses a dirty tree and writes files atomically | `133ce96` | #1282 | this session |
| #1386 shared plaintext-endpoint tables pinned | `35890ca` | #1293 | this session |
| #1387 Windows redactor leaves prose after "Basic" alone | `8e952f9` | #1286 | this session |
| #1388 the fast Swift parse gate parses the test sources | `88ccb5f` | #1281 | this session |
| #1389 the classifier's own documentation says what the code does | `9fb630f` | #1290 | this session |

Each landed with an independent fresh-context review on its exact head, required checks green, squash-only
merge (the org ruleset "Public repositories: changes to main through pull requests" allows `squash` only,
and as of this session requires **0** approving reviews — it previously required 1).

No pull requests are open; `main` is `9fb630fbcef4`.

**The batch of five, and what each one changed:**

- **#1282** — `scripts/bump_version.sh` refused to run on a dirty tree and wrote all four files through a
  temporary file and a rename, so a reader never sees half-written file and a failed write leaves the
  previous contents in place. The gate is `scripts/check-version-bump-guard.sh`, wired into the validation.
- **#1293** — the shared plaintext-endpoint tables are pinned: their size and the rows that carry the
  security decisions, by one check that runs on every pull request and by both ports' own suites. A
  deleted row used to fail silently on both ports.
- **#1286** — the Windows diagnostics redactor no longer rewrites prose after the word "Basic". It
  decodes the candidate and redacts it only when the decoded bytes are text with a colon in it and text on
  both sides of the colon. The rule was decided by counting false positives over the repository's own
  words: no English word and four identifiers are flagged, where a looser rule flagged 310.
- **#1281** — the fast Swift parse gate parses the test sources too. It is pinned by a hermetic gate that
  runs the real gate with a stub toolchain, so the property holds on every pull request.
- **#1290** — the classifier's own documentation, on both ports and their tests, now says what the code
  does. Comment-only: mechanically verified to change no code.

**One thing to know about #1383:** the owner merged it at head `e55f07b`, which had been fixed but **not
independently reviewed** — the review of its predecessor `5d8908f` found one P1 (the watchdog signalled one
process group, so deeper nesting levels survived and kept cloning), a P2 (a committed machine-local
symlink) and documentation overstatements, and the fixes for those were verified locally but not reviewed.
The state of the pull request said so before it was merged. The merged content is the intended one: the
descendant walk is in place, the symlink is gone, and the comments and changelog no longer claim more than
the code does. That review is still outstanding.

What that gate does, and what it does not: it enforces that `VERSION`, `project.yml`'s
`MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` and the latest released heading in `CHANGELOG-archive.md`
agree, on every validation run; it proves by running that the check still catches drift; and it proves by
cloning the repository that a genuine drift fails the validation. Its remaining limits are stated in its own
comments and changelog.

## Reviewer routes

Kimi K2.8 (`kimi-code-plan-cn/kimi-for-coding`) is **available again** — the allowance that was exhausted
when this file was first written has reset, and it was used for the later reviews in this batch. MiniMax
M3 (`minimax-coding-plan/MiniMax-M3`) works and remains usable as a fallback; the same model in a fresh
context counts as independent. OpenCode Go models need an authenticated key this sandbox does not have
(the `opencode` provider is configured with `apiKey: public`, which serves only the free models, and those
are rate-limited).

Two findings in this batch were against the author's own work and would have shipped: a test that assumed
`PATH="/usr/bin:/bin"` is toolchain-free (it is not on macOS, where Xcode puts `swiftc` in `/usr/bin`),
and a redaction rule that let credentials through which the pattern it replaced always caught. Both were
found by re-deriving the behaviour rather than by reading the diff.

## Remaining board candidates (all admissible: no `ai/blocked`, no PR, no in-development label)

- **#1291** — the settings screen's single-render decision is not pinned by a test. Either a
  `BugNarratorUITests` test (needs a desktop session, so it cannot be run here) or the decision moved
  fully into the store, which only CI can prove. The highest-value item left that is still small.
- **#1277** — the macOS app carries a dead review tab model with live tests. Pure removal.
- **#1287** — the documents describe CodeQL as a scheduled-only workflow and do not say which one. The
  wording is now partly wrong in the other direction, because the workflow is disabled — see below.

## Notes for whoever picks this up

- **The repository's own code-scanning workflow is disabled.** `.github/workflows/codeql.yml` is live at
  `disabled_manually`, while `docs/operations/deployment.md` says the workflow "is enabled". The monthly
  run of 2026-11-01 and the last run of any kind, of 2026-11-11, were both cancelled, so the repository's
  Swift code has never completed a CodeQL analysis. GitHub's own default workflow, also named "CodeQL",
  is `active`, so a maintainer reading the wrong one sees results that say nothing about this repository.
  Re-enabling it is a settings change and was not attempted; the documents should give the command that
  settles the state (`gh api repos/SureForgeTech/sureforge-capture/actions/workflows/codeql.yml --jq
  .state`) rather than assert one.
- The org ruleset changed mid-session: `required_approving_review_count` is now 0, so a PR can be merged
  without an approval from another account. `dismiss_stale_reviews_on_push` and
  `required_review_thread_resolution` are still on, and `squash` is still the only allowed method.
- **A conflicting pull request gets no CI.** PR #1387 was opened against a base that had moved and sat
  CONFLICTING; GitHub ran no `pull_request` workflow at all, because it cannot create the merge ref.
  Merge `main` into the branch *before* opening the pull request.
- `scripts/validate.sh` is the declared validation and CI's `runtime-guardrails` entry point. Run it with
  `VALIDATE_SKIP_BOARD_AUDIT=1` (CI does the same).
- The Windows and macOS test suites cannot run in this Linux sandbox (no `dotnet`, no Swift toolchain); the
  Swift parse check and the Xcode suite report `NOT RUN` here, and CI's `macos-26` and `windows-latest` jobs
  are the real evidence for Windows and macOS changes.
- Never commit `local-transcription/venv` or `site/node_modules`; they are gitignored and must stay that way.
  An earlier commit in this session accidentally tracked a symlink to a machine-local path and it was removed.
