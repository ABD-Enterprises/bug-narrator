# Rollback

BugNarrator rollback currently focuses on release-artifact rollback rather than service failover because the product is shipped as a local desktop app.

## When To Roll Back

Use rollback when a published build introduces:

- broken install behavior
- signing, notarization, or Gatekeeper failures
- permission regressions
- recording or screenshot regressions
- corrupted export or session artifacts

## Rollback Strategy

1. Identify the last known good released tag and DMG.
2. Confirm the previous DMG is still available or rebuild it from the tagged commit if necessary.
3. Re-publish or re-promote the last known good DMG on GitHub Releases.
4. Update release notes or pinned issue guidance so testers know which version to use.
5. If a stable asset link is affected, restore `BugNarrator-macOS.dmg` to the last known good artifact.
6. Capture the incident and follow-up remediation in [docs/roadmap/roadmap.md](../roadmap/roadmap.md).

## Local Rollback Support

For local validation environments:

- switch back to the prior git tag or commit
- rerun `./scripts/release_smoke_test.sh`
- rebuild the DMG with `./scripts/build_dmg.sh`

## Rollback Validation

After rollback:

- verify the DMG opens normally
- verify the app launches
- verify microphone and screenshot workflows behave as expected
- verify the release metadata and download links are coherent

## Related Docs

- [Deployment](deployment.md)
- [Release Process](../release/release-process.md)
