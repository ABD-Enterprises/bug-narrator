# BugNarrator Distribution

This document explains how to build the BugNarrator release app and package it as a distributable macOS DMG.

## What This Produces

The packaging workflow creates:

- a Release build of `BugNarrator.app`
- a DMG containing `BugNarrator.app`
- an `Applications` shortcut inside the DMG
- two output filenames in `dist/`

By default you will get:

- `BugNarrator-vX.Y-macOS.dmg`
- `BugNarrator-macOS.dmg`

The non-versioned filename is useful for a stable GitHub Releases download link.

## Prerequisites

- Xcode installed
- the generated project file `BugNarrator.xcodeproj`
- `hdiutil`, which is included with macOS

If you changed `project.yml`, regenerate the Xcode project first:

```bash
xcodegen generate
```

## Quick Command

From the repository root:

```bash
./scripts/build_dmg.sh
```

## What The Script Does

The script:

1. builds the app in `Release`
2. stages `BugNarrator.app`
3. adds an `Applications` symlink
4. creates a compressed DMG
5. writes the finished artifacts to `dist/`

## Output Location

By default the script writes:

- the DMG files to `dist/`
- intermediate build data to `build/DerivedData`

## Release Signing Notes

The script defaults to:

```bash
CODE_SIGNING_ALLOWED=NO
```

This makes the packaging workflow reproducible on machines that do not have Apple signing configured.

For a public release, you should normally:

1. install a `Developer ID Application` certificate for your Apple Developer account
2. configure a notarization credential profile for `notarytool`
3. build with Developer ID signing enabled
4. notarize and staple the final DMG

You can override the script behavior if needed. For a locally signed build using the configured Apple team:

```bash
CODE_SIGNING_ALLOWED=YES \
CODE_SIGN_STYLE=Automatic \
DEVELOPMENT_TEAM=YOURTEAMID \
ALLOW_PROVISIONING_UPDATES=YES \
./scripts/build_dmg.sh
```

That produces a signed app inside the DMG if your local machine has a valid signing identity for that team.

For broad public distribution outside your own Mac, you should use `Developer ID Application` plus notarization. An `Apple Development` signature is better than unsigned for local validation, but Gatekeeper will still reject it for normal public download flows.

### Developer ID And Notarization

First, store a notarization credential profile in your keychain:

```bash
xcrun notarytool store-credentials ***REMOVED*** \
  --apple-id YOUR_APPLE_ID \
  --team-id YOUR_TEAM_ID \
  --password YOUR_APP_SPECIFIC_PASSWORD
```

Then build, notarize, staple, and validate in one command:

```bash
CODE_SIGNING_ALLOWED=YES \
CODE_SIGN_STYLE=Automatic \
CODE_SIGN_IDENTITY=\"Developer ID Application\" \
DEVELOPMENT_TEAM=YOUR_TEAM_ID \
ALLOW_PROVISIONING_UPDATES=YES \
NOTARIZE=YES \
NOTARY_PROFILE=***REMOVED*** \
./scripts/build_dmg.sh
```

The packaging script will:

1. build the Release app
2. verify the app is signed
3. create the DMG
4. submit the DMG to Apple's notarization service
5. staple the notarization ticket to the DMG
6. run `stapler validate` and `spctl` checks

## Releasing On GitHub

Recommended flow:

1. run `./scripts/build_dmg.sh`
2. create a GitHub Release
3. upload `dist/BugNarrator-macOS.dmg`
4. optionally upload the versioned `dist/BugNarrator-vX.Y-macOS.dmg`
5. update release notes and changelog if needed

## Verify The DMG

After building:

1. open the DMG in Finder
2. confirm `BugNarrator.app` is present
3. confirm the `Applications` shortcut is present
4. drag the app into `Applications`
5. launch the installed app and verify first-run behavior

For a public release, also verify:

1. `xcrun stapler validate dist/BugNarrator-vX.Y-macOS.dmg`
2. `spctl -a -vv -t open dist/BugNarrator-vX.Y-macOS.dmg`
3. Gatekeeper accepts the downloaded DMG on a second Mac that has never built the app locally

## Related Docs

- [README.md](../README.md)
- [Quickstart](../QUICKSTART.md)
- [Release Checklist](RELEASE_CHECKLIST.md)
