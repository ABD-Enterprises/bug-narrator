# Deployment

BugNarrator is currently distributed as a signed macOS desktop application through GitHub Releases.

There is no hosted backend deployment at this time. Deployment therefore means packaging, signing, notarizing, validating, and publishing the app and DMG artifacts.

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
2. Build the DMG with `./scripts/build_dmg.sh`
3. For public distribution, sign with `Developer ID Application`, notarize, and staple
4. Publish the DMG artifacts to GitHub Releases
5. Validate the public download on a second Mac when practical

## Production Artifact Targets

Current production artifacts:

- `BugNarrator-macOS.dmg`
- `BugNarrator-vX.Y.Z-macOS.dmg`

These are produced by `scripts/build_dmg.sh`.

## Deployment Controls

- do not publish an unsigned DMG as the production artifact
- do not publish if microphone entitlement validation fails
- do not publish if smoke validation or targeted regression checks fail
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

## Terraform Scope

`infra/terraform` currently provides reproducibility scaffolding for future distribution automation and environment metadata. It does not yet provision active runtime infrastructure because the product is a local desktop application.

## Related Docs

- [Rollback](rollback.md)
- [Release Process](../release/release-process.md)
- [Distribution Companion](../Distribution.md)
