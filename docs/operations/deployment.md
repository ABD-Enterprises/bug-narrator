# Deployment

BugNarrator is currently distributed as a signed macOS desktop application through GitHub Releases.

There is no hosted backend deployment at this time. Deployment therefore means packaging, signing, notarizing, validating, and publishing the app DMG and the optional Local Parakeet server artifacts.

## Current Environments

- `dev`
  local maintainer builds and branch validation
- `test`
  manual release-candidate validation on signed or unsigned candidate builds
- `prod`
  public GitHub Releases artifacts

## Current Deployment Flow

1. Validate the current workspace with:
   - `./scripts/release_smoke_test.sh`
   - any focused manual QA from [docs/QA_CHECKLIST.md](../QA_CHECKLIST.md)
2. Confirm the separately gated UI tests pass in CI or a usable interactive window-server session; the release smoke script remains headless
3. Review Dependabot, CodeQL, and secret-scanning alerts; fix or formally document every finding
4. If the local transcription server changed, build and behavior-test it with `local-transcription/build_standalone.sh`
5. Build the DMG with `./scripts/build_dmg.sh`
6. For public distribution, Developer ID sign and notarize both artifact families; staple the app and DMG
7. Publish the app and local-server artifacts, checksums, and provenance to GitHub Releases
8. Validate the public downloads on a second Mac when practical

## Production Artifact Targets

Current production artifacts:

- `BugNarrator-macOS.dmg`
- `BugNarrator-vX.Y.Z-macOS.dmg`
- `bugnarrator-transcription-macos-arm64.dmg`
- `bugnarrator-transcription-vX.Y.Z-macos-arm64.dmg`
- SHA-256 and provenance files for each published artifact family

The app DMGs are produced by `scripts/build_dmg.sh`; the server DMGs are produced by `local-transcription/build_standalone.sh`.

## Deployment Controls

- do not publish an unsigned DMG as the production artifact
- do not publish if microphone entitlement validation fails
- do not publish if smoke validation or targeted regression checks fail
- do not publish a local-server DMG unless its packaged generated-speech transcription passes and its stapled ticket validates
- do not publish if secrets or signing credentials are missing and the release is intended to be public

## GitHub Workflow Support

The repo now includes lightweight GitHub workflow support for non-release automation:

- `.github/workflows/ci.yml`
- `.github/workflows/codeql.yml`

The production release path remains locally controlled and documented. GitHub Actions do not compile, sign, notarize, or package the macOS app.

## Docs Site Publication

The Docusaurus docs site publishes automatically. `.github/workflows/docs-site.yml`
builds and deploys to GitHub Pages on every push to `main` that touches `site/`,
`docs/`, or the workflow itself, and can also be run on demand with
`workflow_dispatch`.

The build fails rather than publishing if a generated site mirror is stale, so
the live pages cannot silently disagree with the canonical repo docs. Regenerate
with:

```
python3 scripts/sync_site_docs.py
```

Pages is served from the **GitHub Actions** source. The legacy `gh-pages` branch
is no longer the publish target; it is left in place as a historical artifact.

Manual fallback, if the workflow is unavailable:

1. `npm ci --prefix site && npm run build --prefix site`
2. publish `site/build` to the Pages source

Before this workflow existed, publication was manual and had not run since
2026-05-11 — the live site served pre-transfer repository links for three
months while `main` was correct. That is the failure mode automating this
removes.

## Update Channel

Installed copies check for updates by reading the repository's public
`releases/latest` endpoint when the user picks **Check for Updates**. There is
no appcast, no background polling, and no launch-time check — the read happens
only on that explicit action.

The request is unauthenticated and carries no identifiers: no token, no install
id, no version reporting. Nothing about the user is transmitted; the app reads
a public JSON document and compares tag to bundle version locally.

Behavior:

- newer release published → opens that release's page
- already current → says so, opens nothing
- check fails → says the check failed and opens the releases page, so the
  action never dead-ends

Because the channel is the GitHub releases feed, **publishing a release is what
ships an update notice**. A build that is never released is invisible to
installed users.

## Terraform Scope

`infra/terraform` currently provides reproducibility scaffolding for future distribution automation and environment metadata. It does not yet provision active runtime infrastructure because the product is a local desktop application.

## Related Docs

- [Rollback](rollback.md)
- [Release Process](../release/release-process.md)
- [Distribution Companion](../Distribution.md)
