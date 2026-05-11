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

The Docusaurus docs site is published separately from the macOS app release flow.

Current manual publish path:

1. run `npm run build --prefix site`
2. run `cd site && GIT_USER=deffenda USE_SSH=false npx docusaurus deploy`
3. if the `gh-pages` branch does not exist yet, publish the built `site/build` output to a new `gh-pages` branch first, then rerun the deploy command
4. confirm the site resolves at `https://deffenda.github.io/bug-narrator/`

This keeps docs publication reproducible without adding new recurring GitHub Actions jobs.

## Terraform Scope

`infra/terraform` currently provides reproducibility scaffolding for future distribution automation and environment metadata. It does not yet provision active runtime infrastructure because the product is a local desktop application.

## Related Docs

- [Rollback](rollback.md)
- [Release Process](../release/release-process.md)
- [Distribution Companion](../Distribution.md)
