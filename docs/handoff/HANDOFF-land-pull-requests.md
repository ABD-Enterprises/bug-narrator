# HANDOFF — land-pull-requests (SureForgeTech/sureforge-capture)

## Goal

Land the open pull requests on `SureForgeTech/sureforge-capture` with a substantive independent
review on each exact head, and work through the backlog items that follow. Both are done for the
batch of five: ten pull requests merged into `main`, five issues closed in this batch, no pull
request open.

## What is done, and whether it is tested

Ten pull requests merged into `main` (`9fb630fbcef4`); five issues closed in this batch; no pull
request is open.

| PR | Commit | Issue | Merged by | Reviewed |
|---|---|---|---|---|
| #1354 corrupt-audio fixture prepared before the finalization timer starts | `668ce5f` | #1353 | this session | yes — MiniMax M3 |
| #1368 Windows Ctrl+C-ignore flag normalised in the test host | `faa6192` | #1366 | this session | yes — MiniMax M3 |
| #1365 Session Library navigation/actions reachable in smaller windows | `da40c3a` | #1363 | this session | yes — MiniMax M3 |
| #1382 version contract enforced by the validation gate | `01c076d` | #1276 | the owner | yes — MiniMax M3, five rounds |
| #1383 gate hardening: nesting bounded, released heading pinned | `2c05bb6` | — | the owner | **see "half-done"** |
| #1384 version bump refuses a dirty tree and writes files atomically | `133ce96` | #1282 | this session | yes — MiniMax M3, six rounds |
| #1386 shared plaintext-endpoint tables pinned | `35890ca` | #1293 | this session | yes — MiniMax M3, two rounds |
| #1387 Windows redactor leaves prose after "Basic" alone | `8e952f9` | #1286 | this session | yes — MiniMax M3 then Kimi K2.8, three rounds |
| #1388 the fast Swift parse gate parses the test sources | `88ccb5f` | #1281 | this session | yes — Kimi K2.8, three rounds |
| #1389 the classifier's own documentation says what the code does | `9fb630f` | #1290 | this session | yes — Kimi K2.8, three rounds |

Tested: `./scripts/validate.sh origin/main` exits 0 on every merged tree (semgrep via local PATH,
shellcheck 28 scripts, ruff 9 scripts, 86 local-transcription unit tests, contract/spec checks,
accessibility checks, owner-identifier audit). The Windows and macOS suites cannot run in this Linux
sandbox (no `dotnet`, no Swift toolchain); CI's `windows-latest` and `macos-26` jobs were the real
evidence for the Windows and Swift changes.

## What is half-done

**PR #1383's head `e55f07b9858206b748eef224ab81e8e05002ee7a` was merged without an independent review of
that exact head.** The review of its predecessor `5d8908f` found one P1 (the watchdog signalled a single
process group, so deeper nesting levels survived and kept cloning), one P2 (a committed machine-local
symlink) and documentation overstatements. Those were fixed in `e55f07b` and verified locally, but no
reviewer looked at `e55f07b`. The pull request recorded this state before it was merged.

The unreviewed change, in `scripts/check-version-consistency-gate.sh` on `main`:

- `kill_tree()` helper — walks descendants and stops each, replacing a process-group signal.
- the workspace created inside the tree, so the trap reclaims every nested clone.
- the watchdog's process-group handling removed and the descendant walk used instead.

Locally verified after the fix: once the watchdog fires, no `git clone` or nested `validate.sh` process
survives and no temporary directory is left behind (0 processes, 0 temp directories).

**Still to do on that:** an independent fresh-context review of `scripts/check-version-consistency-gate.sh`
at `origin/main`, with the package fixture that defeats the old watchdog: a committed version check that
tolerates the clone's `VERSION=0.0.0` while still rejecting the gate's step-2 probe shapes, plus a
committed validator that rewrites `artifacts/validation/version-gate-depth` to `0`. Confirm that the
watchdog then leaves no surviving processes and no leaked directories.

**Not started:** #1291 (the settings screen's single-render decision is not pinned by a test), #1277
(the macOS dead tab model), #1287 (the CodeQL documents).

## Exact next step

1. Review the version gate as described under "half-done" above, and post the verdict.
2. Then **#1291** — "The settings screen's single-render decision is not pinned by a test". The fix
   either adds a `BugNarratorUITests` test (which needs a desktop session, so it cannot be run here) or
   moves the decision fully into the store, which is a real Swift change that only CI can prove. It is
   the highest-value item left that is still small.
3. Then **#1277** and **#1287**, both small.

## Branch, commit, pull request

- Working checkout: `/workspace/sureforge-capture`, branch `fix/1286-windows-basic-redaction` at
  `f234e0a` (the merged PR #1387 branch); `main` is at `9fb630f`.
- Worktrees: `/tmp/opencode/w/wt-1281` (`fix/1281-swift-parse-tests`, merged), `/tmp/opencode/w/wt-1290`
  (`fix/1290-classifier-comment-accuracy`, merged) and `/tmp/opencode/w/wt-handover`
  (`wip/land-pull-requests`). All three hold merged work and can be deleted.
- WIP branch created for this session: `wip/land-pull-requests` (see the final reply for its commit).
- Open pull requests: none.

## Decisions made, and why

- **Squash-only merge.** The org ruleset "Public repositories: changes to main through pull requests"
  allows `squash` alone. `--admin` was used only where the merge was blocked by a conflict, not to skip
  a required check.
- **Merge `main` into a stale branch rather than rebasing it.** The fleet rules forbid force-pushing or
  rebasing a branch another session may own; a merge keeps the owner's branch intact. Every conflict was a
  `CHANGELOG.md` content conflict, resolved by keeping both sides' entries.
- **Merge `main` into the branch before opening the pull request.** PR #1387 was opened against a base
  that had moved and sat CONFLICTING; GitHub silently ran no `pull_request` workflow at all, because it
  cannot create the merge ref. A conflicting pull request gets no CI at all.
- **Kimi K2.8 is available again.** The earlier session recorded that every Kimi variant was out of
  allowance; the allowance reset, and `kimi-code-plan-cn/kimi-for-coding` has worked for every review
  since. MiniMax M3 remains usable as a fallback.
- **Measured the redaction rule instead of arguing about it.** The Windows Basic rule was decided by
  counting false positives over the repository's own words: 3,624 English words and 11,483
  identifier-shaped words. Requiring the decoded bytes to be valid UTF-8 flags no English word and four
  identifiers; the looser rule flagged 310 identifiers, and searching a run through rather than at its
  two ends flagged 55. The rule that shipped is the one with the fewest false positives that still
  catches a credential in every realistic position.
- **Did not search the whole run for a credential.** A credential with base64 characters on both sides of
  it is not found, because doing so is what flags ordinary identifiers. The limitation is stated in the
  code comment and in the pull request body rather than hidden.
- **Built the toolchain-free path rather than assuming one.** The Swift parse gate's test needed a
  machine with no Swift toolchain; `PATH="/usr/bin:/bin"` is not one on macOS, where Xcode puts
  `swiftc` in `/usr/bin`. The path is now assembled from the tools the gate actually needs.
- **Kept the version gate's limits stated rather than adding mechanisms.** The gate's remaining limits —
  a committed change that prints the version failure line, or that rewrites the depth marker — are stated in
  its own comments and changelog, because they are committed changes whose review is what catches them.
- **Did not commit `local-transcription/venv` or `site/node_modules`.** Both are gitignored; an earlier
  commit in this session accidentally tracked a symlink to a machine-local path and it was removed in
  #1383.

## Blockers

None blocking the next step. Two environmental limits worth recording:

- **The repository's own code-scanning workflow is disabled.** `.github/workflows/codeql.yml` is live at
  `disabled_manually`, while `docs/operations/deployment.md` says the workflow "is enabled". The monthly
  run of 2026-11-01 and the last run of any kind, of 2026-11-11, were both cancelled, so the repository's
  Swift code has never completed a CodeQL analysis. GitHub's own default workflow, also named "CodeQL",
  is `active`, so a maintainer reading the wrong one sees results that say nothing about this repository.
  Re-enabling it is a settings change and was not attempted.
- OpenCode Go models: the `opencode` provider here is configured with `apiKey: public`, which serves only
  the free models, and those return
  `Free usage limit reached. Free models work in OpenCode (https://opencode.ai); subscribe to OpenCode Go
  to keep going: https://opencode.ai/go`. Probing a Go model directly returns
  `{"type":"error","error":{"type":"AuthError","message":"Missing API key."}}`. A Go subscription key is
  therefore needed for that route.

## Ignored and untracked files that matter

`git status --ignored --short` on `/workspace/sureforge-capture`:

```
!! .ruff_cache/
!! artifacts/
!! build/
!! local-transcription/__pycache__/
!! local-transcription/venv/
!! site/.docusaurus/
!! site/build/
!! site/node_modules/
```

- `local-transcription/venv/` — the Python venv for the local-transcription unit tests. Installed with
  `parakeet-mlx` filtered out, exactly as CI does, because it is Apple-only. **Keep it**: it is the
  interpreter the validation and the 86 local-transcription unit tests run under.
- `site/node_modules/` — the docs-site dependencies, installed with `./scripts/site_npm.sh ci` (the
  repository's own pinned-toolchain wrapper). **Keep it**: `npm ci` takes about a minute to redo.
- `artifacts/`, `build/`, `site/build/`, `site/.docusaurus/`, `.ruff_cache/`,
  `local-transcription/__pycache__/` — generated run evidence and caches. Safe to delete; nothing in them
  is needed to resume.
- `/tmp/opencode/w/wt-1281`, `/tmp/opencode/w/wt-1290` and `/tmp/opencode/w/wt-handover` — the three
  worktrees of this batch. All hold merged work; they can be deleted.
