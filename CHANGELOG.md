# Changelog

## Unreleased

- [SECURITY] Stop publishing the owner's notarization identifiers: the Apple ID, development team ID, notary keychain profile name and password-manager item name are out of the published documentation, and a new audit wired into `./scripts/validate.sh` keeps them out of every tracked file (#1275)
- [SECURITY] The signing and notarization settings no longer live in this public repository at all: `scripts/build_dmg.sh` and `local-transcription/build_standalone.sh` read them from the machine-local signing settings, the app pins its server publisher from the team the build injects into the bundle, and the documentation audit no longer needs to know the values to keep them out (#1275)
