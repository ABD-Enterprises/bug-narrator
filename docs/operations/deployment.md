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

The repo now includes workflow scaffolding for CI and manual release packaging:

- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`

The current production release path remains locally controlled and documented. The workflow scaffolding is intended to reduce drift and prepare for fuller automation, not to replace already-working signed local release steps before secrets and runner validation are proven.

## Terraform Scope

`infra/terraform` currently provides reproducibility scaffolding for future distribution automation and environment metadata. It does not yet provision active runtime infrastructure because the product is a local desktop application.

## Related Docs

- [Rollback](rollback.md)
- [Release Process](../release/release-process.md)
- [Distribution Companion](../Distribution.md)
