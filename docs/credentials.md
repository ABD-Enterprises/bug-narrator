# Credentials

This page routes each credential question to where the answer actually lives.
The repository is public, so nothing on it is a secret and nothing here should
ever become one.

## What this repository decides

**Application secrets** — OpenAI, GitHub, and Jira credentials entered by the user
in Settings — are governed by [Security → Secret Handling](security/security.md#secret-handling).
That section is authoritative for how the app stores, redacts, and exports them.

**Release signing and notarization** — the Developer ID certificate, the
`notarytool` keychain profile, and the Apple app-specific password — are
governed by the [release process](release/release-process.md). Those live in the
operator's login keychain and password manager, never in the repository.

**Test isolation** — `AppBootstrap` builds an in-memory keychain under the
isolated test runtime, so tests never touch the real keychain. The launch-time
hooks that seed that runtime (`BUGNARRATOR_TEST_*`) are self-guarding and only
honoured when `usesIsolatedRuntime` is true.

## What the agent rules decide

How an agent session reaches a local secret manager or the keychain is set by
`AGENTS.md` and the operator's own machine rules, not by this repository. The one
rule that matters most here: a sandboxed `op`/`cred`/keychain call fails
misleadingly, and that is the sandbox, not an auth failure.

Nothing on this page is a secret and nothing here should ever become one.
