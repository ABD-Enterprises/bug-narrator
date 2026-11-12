# Changelog

## Unreleased

- [SECURITY] Stop publishing the owner's notarization identifiers: the Apple ID, development team ID, notary keychain profile name and password-manager item name are out of the published documentation, and a new audit wired into `./scripts/validate.sh` keeps them out of every tracked file (#1275)
