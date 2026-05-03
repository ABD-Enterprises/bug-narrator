# Security

This is the canonical structured security document for BugNarrator. It complements the shorter top-level [SECURITY.md](../../SECURITY.md).

## Security Model

BugNarrator is a local desktop application with user-supplied credentials.

Primary security boundaries:

- local app runtime on macOS
- user-provided OpenAI, GitHub, and Jira credentials
- local session artifacts and diagnostics
- release signing, notarization, and publication workflow

## Secret Handling

BugNarrator must never store or expose secrets in source control, logs, or exported artifacts.

Current approach:

- OpenAI, GitHub, and Jira secrets are stored in macOS Keychain when available
- if secure storage is unavailable, credentials are kept in memory only for the active run
- debug bundle export excludes raw secrets
- logs must not include authorization headers, tokens, or API keys

## Permission Model

BugNarrator requests permissions only when required for the user action:

- microphone permission when starting a recording
- Screen Recording permission when capturing screenshots

BugNarrator does not require Accessibility permission for the core workflow.

## Current Security-Sensitive Areas

- release signing and notarization credentials
- secure secret storage and migration behavior
- remote API request handling
- debug bundle and diagnostic export safety
- issue export integrations

## Known Security And Reliability Risks

Tracked active risks include:

- Windows release and runtime security posture has not yet been validated on Windows hardware

Track these in [GitHub Issues](https://github.com/deffenda/bugnarrator/issues). Use [docs/roadmap/roadmap.md](../roadmap/roadmap.md) only for historical roadmap context.

## Security Validation Expectations

When changing sensitive code paths, validate:

- no secret leakage in logs
- no secret leakage in debug bundles
- permission gating remains explicit and least-privilege
- invalid credentials fail clearly and safely
- release artifacts retain required entitlements and signing identity

## Related Docs

- [Product Spec](../architecture/product-spec.md)
- [Top-Level Security Notes](../../SECURITY.md)
- [Testing Guide](../testing/testing.md)
- [Release Process](../release/release-process.md)
