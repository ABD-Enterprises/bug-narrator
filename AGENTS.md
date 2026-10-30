# Agent instructions: bug-narrator

<!-- fleet-core:begin (generated: edit the fleet source, not this block) -->
## Fleet core

Applies to every repository in the fleet. It is generated from one source; repository-specific rules go outside the markers.

### Evidence
- Read live state before stating it: fetch the remote, read the default branch, run the command. A number or an "X is missing" taken from a doc or a stale checkout is a claim to verify. A figure in a doc carries its date and how it was read.
- Find the root cause before proposing a remedy. For an unreachable or hung host, check its network interface and the previous boot's log before blaming memory.
- Give one account of a fact. If two places disagree, fix or flag one.
- Say plainly what you did not verify.

### Changes
- One bounded task per change request. Stay in scope: no drive-by edits and no agent scratch files committed.
- Run the repository's validation (named below) before pushing.
- A change request merges when a fresh-context review of the exact head has no unresolved P0 or P1 findings and every required check is green. A new commit needs a new review; a clean automatic merge of the base branch keeps the review.
- At most three open non-draft change requests per repository. While the fleet backlog check reports a backlog, finish and land existing work and start nothing new.
- Fix a finding that takes minutes in the current change; fold the rest into an existing tracking issue. A session closes at least as many issues as it opens on its own initiative; tickets the owner asks for in chat are separate.

### Safety
- Never print, log or commit tokens, passwords or keys. Use the credential helper the repository names.
- One writer per checkout: separate worktrees for separate writers. Do not force-push, rebase or delete a branch another session may own.
- Private repositories run CI on self-hosted runners only. A job that must not share a host (for example signing) runs on a dedicated self-hosted runner group, never on a GitHub-hosted runner without the owner's approval.
- Ask the owner only for a step no agent can do or for a spend or legal commitment; decide and record everything else.

### Layout
- AGENTS.md is the canonical agent file; where a CLAUDE.md exists it only imports it. Keep this file under 200 lines.
- Name this repository's validation command, merge rule and changelog rule outside the markers. Rules kept outside the repository are not visible here: if a task seems to need one, ask rather than guess.
- Shared skills are installed per machine from the fleet skills hub. Name the ones this repository expects below.

### Forge: GitHub
- Prefer REST (`gh api repos/OWNER/REPO/...`) to GraphQL for single reads: the rate-limit pools are shared by every session on the account.
- Required checks and review rules are branch protection or rulesets; read them with `gh api`. Review-thread resolution needs GraphQL.
<!-- fleet-core:end -->

## Repository-specific

- Public repository: the files are world-readable, and so is anything an agent writes into the repository, including issues, pull requests and comments. Keep customer, tenant and internal-host names, private paths, tokens and personal data out of all of it. Hosted GitHub runners are allowed here because the no-hosted-runner rule covers private repositories only.
- What it is: BugNarrator, a macOS menu bar app (Swift, `BugNarrator.xcodeproj` generated from `project.yml` with xcodegen) that records narrated test sessions, transcribes them and extracts issues; plus a Windows port (`windows/`, .NET 8) and a local transcription server (`local-transcription/`, Python).
- Layout: Swift sources in `Sources/BugNarrator`, tests in `Tests/BugNarratorTests` and `Tests/BugNarratorUITests`, Windows code in `windows/`, the Python server in `local-transcription/`, docs in `docs/` (product spec `docs/architecture/product-spec.md`), docs site in `site/`, release and check scripts in `scripts/`.
- Validation: run `./scripts/validate.sh origin/main` before pushing; it is the entry point CI's `runtime-guardrails` job runs. It checks the product-spec contract, the changed-files self-check (the gate fails closed when it cannot diff against the base ref), Semgrep on changed files, Swift parsing, the repository docs, the agent-file layout (`scripts/check-agent-rules-sync.sh`), shellcheck and ruff. Run it with `VALIDATE_SKIP_BOARD_AUDIT=1` to skip the live issue-board audit (CI does the same). It uses Docker for Semgrep when Docker is running and passes `SEMGREP_APP_TOKEN` from your environment into that container if the variable is set; do not set it. App build and tests: `xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug -destination 'platform=macOS' -only-testing:BugNarratorTests CODE_SIGNING_ALLOWED=NO test`. `scripts/verify.sh` chains validate.sh and the Swift parse check and does not build.
- Merge: the fleet core's merge rule applies. GitHub enforces the organization ruleset "ABD default branch baseline" (no deletion or force push) and branch protection on `main` that requires the checks `detect-ci-changes`, `runtime-guardrails` and `required-checks` (no required reviews, signatures or up-to-date branch), read 2026-10-21. CI is `.github/workflows/ci.yml` and also runs on `merge_group`. The macOS build-and-test job (`macos-26`, unit and UI tests) and the Windows job are path-gated and counted by `required-checks`, so a docs-only change does not wait for them.
- Changelog: add an entry under `## Unreleased` in `CHANGELOG.md` (lines like `- [FIX] ...`, `- [SECURITY] ...`, `- [INTERNAL] ...`). `scripts/bump_version.sh` moves them into `CHANGELOG-archive.md` at release time; do not move them by hand.
- Issues: before starting work, check that the issue is open, has no open pull request and is not labelled `ai/blocked` (`gh issue list --repo ABD-Enterprises/bug-narrator --state open`, or `scripts/effort-leak-audit.sh`, which is read-only). If an external credential, signing certificate, account permission or clean-machine check blocks it, say exactly what is missing in the issue and stop; do not add placeholder changes. Run `scripts/effort-leak-audit.sh` before pushing changes to workflows, issue or pull request templates, or release automation.
- Agent files: `AGENTS.md` is the only copy of these rules; `CLAUDE.md` is exactly `@AGENTS.md` and `.agent/rules.md` is a pointer. `scripts/check-agent-rules-sync.sh` (run by validate.sh) fails if either drifts.

### Safety: releases and signing (do not run unless the owner asks)

- Publishing is the owner's step. `scripts/build_dmg.sh` signs, notarizes (`xcrun notarytool`, a keychain profile on the owner's Mac) and staples; with `PUBLIC_RELEASE=YES` it refuses an unsigned, unnotarized, dirty-tree or untagged build (`docs/release/release-process.md`, "Release Guardrails"). Do not run it with `CODE_SIGNING_ALLOWED=YES`, `NOTARIZE=YES` or `PUBLIC_RELEASE=YES`, and do not set `ALLOW_NOTARIZATION_FAILURE`. A plain local build needs none of these (the default is unsigned).
- Two manual (`workflow_dispatch`) workflows create GitHub Releases using the Windows signing secrets: `.github/workflows/windows-tester-release.yml`, and the release path of `.github/workflows/local-transcription-windows.yml` (its pull request and push runs build unsigned and publish nothing). Never dispatch them, and never create or edit releases or tags with `gh`.
- `docs-site.yml` deploys the docs site to GitHub Pages on every push to `main` that touches `site/**` or `docs/**`, so a merged docs change goes live without a separate step. CodeQL runs on a schedule only.
- `scripts/bump_version.sh` edits `VERSION`, `project.yml` and the changelogs together and `scripts/check_version_consistency.sh` checks them; change the version only through the script and only for a release the owner has asked for. `scripts/cleanup_local_build_apps.sh` moves built `BugNarrator.app` copies from Xcode's DerivedData to the Trash; run it only when asked.
- Signing and notarization settings (team, notary profile, Apple account) are defaults inside `scripts/build_dmg.sh`; do not copy them into issues, pull requests or docs, and do not change them without the owner.

### Safety: the app's data and permissions

- The app stores the user's AI, GitHub and Jira credentials in the macOS Keychain and sends recorded audio, transcript text and screenshot names to the configured AI provider (screenshot images only if the user opts in), per the README privacy section. Never feed real recordings, transcripts, screenshots, session folders or keys into a test, issue or pull request. Use fixtures.
- Unit and UI tests run in an isolated runtime (`AppRuntimeEnvironment.usesIsolatedRuntime`): an in-memory keychain, a test-scoped defaults suite and a temporary storage folder, so they do not read the user's real keychain or sessions. Do not weaken that isolation, and do not launch the Release app from `build/` to "try it": it uses the real keychain and may prompt for microphone and screen recording access (`scripts/keychain_startup_smoke_test.sh` and `scripts/release_smoke_test.sh` do this on purpose; run them only when asked). The UI tests launch the app and need a desktop session.
- The app does not require the Accessibility permission for its core workflow (README, `docs/security/security.md`). Do not add code or instructions that ask for it.
- Secrets: `.env`, `.env.*` and `*.local` are ignored, and CI reads the Windows signing certificate from repository secrets. Never print or commit a certificate, password or token; `.gitleaks.toml` and `.gitleaksignore` list reviewed historical exceptions only.
- The `windows/` and `local-transcription/` code cannot be built on a Mac without extra tools; if a change touches them, say what you could not run.

### Skills
- This repository expects no hub skills.
