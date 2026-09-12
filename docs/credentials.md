# Credentials

This page exists because the sure-forge adapter block in `CLAUDE.md` (and its
mirrors `AGENTS.md`, `.agent/rules.md`) ends with "See `docs/credentials.md`". That
block is engine-managed and refers to the engine's own document; in an adopted
repository the relative link would otherwise dangle. This file routes each
question to where the answer actually lives.

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

## What the engine decides

How the sure-forge loop resolves credentials for its own tooling — `.ai/secrets.json`
`exec:` sources, why secret-resolution commands must run with the agent sandbox
disabled, and the portable secrets layer — is the engine's contract, documented in
sure-forge's `docs/credentials.md` ("Credentials for Self-Hosted ORC"). The adapter
paragraph in `CLAUDE.md` summarises the one rule that matters most here: a sandboxed
`op`/`cred`/keychain call fails misleadingly, and that is the sandbox, not an auth
failure.

Nothing on this page is a secret and nothing here should ever become one.
