# Release Process

This is the canonical structured release process for BugNarrator.

Detailed companion docs:

- [Product Spec](../architecture/product-spec.md)
- [docs/Distribution.md](../Distribution.md)
- [docs/RELEASE_CHECKLIST.md](../RELEASE_CHECKLIST.md)
- [CHANGELOG.md](../../CHANGELOG.md)

## Release Guardrails (#963)

A build destined for GitHub Releases must set `PUBLIC_RELEASE=YES`. With it set,
`scripts/build_dmg.sh` refuses to produce an artifact unless all of the
following hold, and it verifies the finished artifact rather than trusting that
the steps ran:

| Requirement | Why |
|---|---|
| clean working tree | an uncommitted change would otherwise ship inside a notarized DMG with nothing recording it |
| `HEAD` exactly on a tag | so a download can be tied to a release |
| `CODE_SIGNING_ALLOWED=YES` | the script's default is `NO`, which produced unsigned artifacts indistinguishable downstream |
| `NOTARIZE=YES` | |
| `ALLOW_NOTARIZATION_FAILURE` unset | that flag combined with a public release is exactly how an unnotarized DMG reaches users |

After building it re-checks the output: the DMG container carries a valid
signature, the DMG has a stapled ticket, and the app bundle is validly signed.
Any of those failing aborts before the artifact is written.

Every build — public or not — writes `dist/<dmg>.provenance.txt` recording the
commit, tag, tree state, signing authority, and whether notarization ran. A
non-public build says so in its summary line.

**The DMG container is now signed.** Previously only the app inside it was;
`codesign -dv` on the shipped 1.0.41 DMG reported "not signed at all".
Notarizing and stapling an image is not the same as signing it.

### Recovering this process on another Mac

The build is not tied to this machine beyond credentials. Another Mac needs:

- Xcode with the matching toolchain, and `DEVELOPER_DIR` pointed at it
- the `Developer ID Application` certificate + private key for team `2R4WAH4R53`
  imported into the login keychain
- a `notarytool` keychain profile named `BugNarratorNotary`
- `python3` (the script bootstraps its own `dmgbuild` virtualenv)

With those in place `PUBLIC_RELEASE=YES CODE_SIGNING_ALLOWED=YES NOTARIZE=YES
./scripts/build_dmg.sh` reproduces a publishable artifact. The remaining
single-point-of-failure is credential custody, not the script.


## Current Release Model

BugNarrator is currently released as a macOS DMG through GitHub Releases.

The authoritative production release path is the locally controlled signing and packaging flow described in `scripts/build_dmg.sh` and the detailed companion docs. macOS build, signing, notarization, and packaging are intentionally local-only so release work does not consume GitHub Actions runner minutes.

## Release Decision Gates

Do not release unless all of these are true:

- smoke validation passes
- relevant tests pass
- manual high-risk QA is complete
- accessibility checks for touched surfaces are complete
- touched user-facing behavior and terminology match the canonical product spec, or the spec is updated in the same change
- signing/notarization inputs are present for a public build
- no unapproved critical or high-severity risk remains

## Current Maintainer Flow

1. Review [GitHub Issues](https://github.com/ABD-Enterprises/bug-narrator/issues) for unresolved risks and active release blockers.
2. Review [Product Spec](../architecture/product-spec.md) for the intended product behavior, terminology, and artifact contract.
3. Update `CHANGELOG.md`.
4. Run `./scripts/release_smoke_test.sh`.
5. Run `./scripts/accessibility_regression_check.sh`.
6. Run any targeted manual QA from [docs/QA_CHECKLIST.md](../QA_CHECKLIST.md).
7. Generate or review the internal release summary seed before publishing.
8. Build the DMG with `./scripts/build_dmg.sh`.
9. For public releases, sign with `Developer ID Application`, notarize, and staple.
10. Publish the DMG assets to GitHub Releases.
11. Validate the published download on a second Mac when practical.

## Versioning

BugNarrator uses semantic versioning:

- major for breaking changes
- minor for meaningful new features
- patch for fixes and internal hardening

The current production application version lives in `VERSION` and the latest GitHub Release.

## GitHub Workflow Scope

The repo now contains:

- `.github/workflows/ci.yml`
- `.github/workflows/codeql.yml`

These workflows support:

- runtime guardrails validation
- lightweight accessibility regression checks for the most accessibility-sensitive macOS surfaces
- docs-site build validation
- code scanning for non-macOS languages

They do not build, sign, notarize, or package the macOS app. Release packaging remains local-only.

## Release Notes Source Of Truth

Use:

- [Product Spec](../architecture/product-spec.md) for intended product behavior and terminology
- `CHANGELOG.md` for shipped or shipping change history
- [GitHub Issues](https://github.com/ABD-Enterprises/bug-narrator/issues) for open risks, active release blockers, and task state
- [docs/roadmap/roadmap.md](../roadmap/roadmap.md) for historical roadmap context and completed phase history

Release notes should match the actual implemented changes and should not contradict the canonical product spec.

The release-summary seed generated by `scripts/generate_release_summary.py` is an internal maintainer aid. It must still be reviewed and edited before it is used in public release notes.

## Related Docs

- [Deployment](../operations/deployment.md)
- [Rollback](../operations/rollback.md)
