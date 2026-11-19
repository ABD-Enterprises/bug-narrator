# HANDOFF — land-pull-requests (SureForgeTech/sureforge-capture)

## Goal

Land the open pull requests on `SureForgeTech/sureforge-capture` with a substantive independent
review on each exact head, and begin the next batch of high-value backlog items. The pull requests
are landed; the feature backlog is not started.

## What is done, and whether it is tested

Five pull requests merged into `main` (`2c05bb64052f962020dc12e59c40c284a9039820`); four issues
closed; no pull request is open.

| PR | Commit | Issue | Merged by | Reviewed |
|---|---|---|---|---|
| #1354 corrupt-audio fixture prepared before the finalization timer starts | `668ce5f` | #1353 | this session | yes — MiniMax M3 + Kimi K3.1 Pro, exact head |
| #1368 Windows Ctrl+C-ignore flag normalised in the test host | `faa6192` | #1366 | this session | yes — MiniMax M3, exact head |
| #1365 Session Library navigation/actions reachable in smaller windows; product-name alignment | `da40c3a` | #1363 | this session | yes — MiniMax M3 over four rounds, exact head |
| #1382 version contract enforced by the validation gate | `01c076d` | #1276 | the owner | yes — MiniMax M3, five rounds |
| #1383 gate hardening: nesting bounded, released heading pinned | `2c05bb6` | — | the owner | **see "half-done"** |

Tested: `./scripts/validate.sh origin/main` exits 0 on the merged trees (semgrep via local PATH,
shellcheck 26 scripts, ruff 8 scripts, 86 local-transcription unit tests, contract/spec checks,
accessibility checks, owner-identifier audit). The Windows and macOS suites cannot run in this Linux
sandbox (no `dotnet`, no Swift toolchain); CI's `windows-latest` and `macos-26` jobs were the real
evidence for the Windows and macOS changes.

## What is half-done

**PR #1383's head `e55f07b9858206b748eef224ab81e8e05002ee7a` was merged without an independent review of
that exact head.** The review of its predecessor `5d8908f` found one P1 (the watchdog signalled a single
process group, so deeper nesting levels survived and kept cloning), one P2 (a committed machine-local
symlink) and documentation overstatements. Those were fixed in `e55f07b` and verified locally, but no
reviewer looked at `e55f07b`. The pull request recorded this state before it was merged.

The unreviewed change, in `scripts/check-version-consistency-gate.sh` on `main`:

- `kill_tree()` helper — lines 97-107 (walks descendants and stops each, replacing a process-group signal).
- the workspace created inside the tree — line 130 (`mktemp -d "$ROOT/artifacts/validation/version-gate-XXXXXX"`),
  so the trap reclaims every nested clone.
- the watchdog's process-group handling removed and the descendant walk used instead — lines 236-268
  (`PROOF_TIMEOUT_SECONDS=300` at line 84, `nested_pid` at line 260).

Locally verified after the fix: once the watchdog fires, no `git clone` or nested `validate.sh` process
survives and no temporary directory is left behind (0 processes, 0 temp directories).

**Not started (not half-done, simply not begun):** the four remaining backlog items of the five-feature
request — #1282, #1281, #1286, #1293 — plus #1290, #1291, #1277.

## Exact next step

1. Run an independent fresh-context review of `scripts/check-version-consistency-gate.sh` at
   `origin/main` (the `kill_tree` helper, the in-tree workspace and the watchdog above), with the
   package fixture that defeats the old watchdog: a committed version check that tolerates the clone's
   `VERSION=0.0.0` while still rejecting the gate's step-2 probe shapes, plus a committed validator that
   rewrites `artifacts/validation/version-gate-depth` to `0`. Confirm that the watchdog then leaves no
   surviving processes and no leaked directories. Post the verdict on the pull request or open a follow-up
   if it finds something.
2. Then start **#1282** — "P3-6: The version bump script runs on a dirty tree and writes files in
   place". It is the highest-value remaining item that can be finished and validated entirely inside this
   sandbox: the owner-prepared branch `origin/fix/guard-the-version-bump` already exists, the change is
   pure shell, and `scripts/bump_version.sh` is exercised end to end in a throwaway copy of the tree.

## Branch, commit, pull request

- Working checkout: `/workspace/sureforge-capture`, branch `main`, at `2c05bb64052f962020dc12e59c40c284a9039820`,
  clean and up to date with `origin/main`.
- WIP branch created for this session: `wip/land-pull-requests` (see the final reply for its commit).
- Open pull requests: none.

## Decisions made, and why

- **Squash-only merge.** The org ruleset "Public repositories: changes to main through pull requests"
  allows `squash` alone. `--admin` was used only where the merge was blocked by a conflict, not to skip
  a required check.
- **Merge `main` into a stale branch rather than rebasing it.** The fleet rules forbid force-pushing or
  rebasing a branch another session may own; a merge keeps the owner's branch intact. Every conflict was a
  `CHANGELOG.md` content conflict, resolved by keeping both sides' entries.
- **Posted the review verdict as a GitHub approving review.** The repo's ruleset now requires 0 approving
  reviews, but the repository's own rule still asks for an independent review of the exact head; the
  bot's approval carries that verdict. For #1382 and #1383 the owner merged, and the state of the pull
  request was stated there.
- **Used MiniMax M3 for the later reviews.** Kimi's provider allowance is exhausted across all six
  variants; MiniMax M3 works and, in a fresh context, counts as independent.
- **Kept the version gate's limits stated rather than adding mechanisms.** The gate's remaining limits —
  a committed change that prints the version failure line, or that rewrites the depth marker — are stated in
  its own comments and changelog, because they are committed changes whose review is what catches them.
- **Did not commit `local-transcription/venv` or `site/node_modules`.** Both are gitignored; an earlier
  commit in this session accidentally tracked a symlink to a machine-local path and it was removed in
  #1383.

## Blockers

None blocking the next step. Two environmental limits worth recording:

- Kimi reviewer's allowance: `You've reached your 5-hour usage limit. Your quota will reset when the
  current 5-hour window ends.` — all six Kimi variants return this; MiniMax M3 is the working fallback.
- OpenCode Go models: the `opencode` provider here is configured with `apiKey: public`, which serves only
  the free models, and those return
  `Free usage limit reached. Free models work in OpenCode (https://opencode.ai); subscribe to OpenCode Go
  to keep going: https://opencode.ai/go`. Probing a Go model directly returns
  `{"type":"error","error":{"type":"AuthError","message":"Missing API key."}}`. A Go subscription key is
  therefore needed for that route.

## Ignored and untracked files that matter (from step 1)

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
- The scratch clone `/tmp/opencode/f2` still exists with the merged branch
  `fix/1382-gate-followup` at `e55f07b`, clean. It is a duplicate of merged work and can be deleted.

## Step 1 output, verbatim

```
$ git status
On branch main
Your branch is up to date with 'origin/main'.

nothing to commit, working tree clean

$ git stash list
(empty)

$ git worktree list
/workspace/sureforge-capture  2c05bb6 [main]

$ git branch -vv
* main 2c05bb6 [origin/main] fix(ci): bound the version gate's nesting and pin the released heading (#1383)

$ git status --ignored --short
!! .ruff_cache/
!! artifacts/
!! build/
!! local-transcription/__pycache__/
!! local-transcription/venv/
!! site/.docusaurus/
!! site/build/
!! site/node_modules/
```
