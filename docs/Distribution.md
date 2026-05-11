# BugNarrator Distribution

Structured counterparts:

- [docs/operations/deployment.md](operations/deployment.md)
- [docs/release/release-process.md](release/release-process.md)

This document explains how to build the BugNarrator release app, package it as a distributable macOS DMG, and validate it before publishing on GitHub Releases.

## What This Produces

The packaging workflow creates:

- a Release build of `BugNarrator.app`
- a DMG containing `BugNarrator.app`
- an `Applications` shortcut inside the DMG
- a custom Finder layout with a drag-to-Applications presentation
- a mounted DMG volume icon that uses the BugNarrator app icon
- validation that branded icon resources are present in the app bundle
- validation that the mounted DMG contains the app plus the `Applications` shortcut
- two output filenames in `dist/`

By default you will get:

- `BugNarrator-vX.Y.Z-macOS.dmg`
- `BugNarrator-macOS.dmg`

The non-versioned filename is useful for a stable GitHub Releases download link.

## Prerequisites

- Xcode installed
- the generated project file `BugNarrator.xcodeproj`
- `hdiutil`, which is included with macOS
- `python3`, which the DMG builder uses to bootstrap `build/dmg-venv` with `dmgbuild` automatically if it is missing

If you changed `project.yml`, regenerate the Xcode project first:

```bash
xcodegen generate
```

## Quick Command

From the repository root:

```bash
./scripts/build_dmg.sh
```

For a quick unsigned release-readiness pass before packaging:

```bash
./scripts/release_smoke_test.sh
```

The release smoke path no longer launches the keychain startup probe by default. If you explicitly want to verify that startup does not trigger a new SecurityAgent prompt, opt in with:

```bash
RUN_STARTUP_KEYCHAIN_SMOKE=YES ./scripts/release_smoke_test.sh
```

## What The Script Does

The script:

1. builds the app in `Release`
2. generates the DMG background art
3. bootstraps `build/dmg-venv` with `dmgbuild` automatically when that packaging environment is missing
4. uses `dmgbuild` to package a styled HFS+ DMG with:
   - `BugNarrator.app`
   - an `Applications` shortcut
   - the BugNarrator mounted-volume icon
   - a clean drag-to-Applications Finder layout
5. verifies `AppIcon.icns` and `Assets.car` exist in the built app
6. mounts the DMG and verifies the expected layout resources
7. writes the finished artifacts to `dist/`
8. when signing is enabled, verifies the built app and mounted DMG app still carry the microphone entitlement required for recording

## Output Location

By default the script writes:

- the DMG files to `dist/`
- intermediate build data to `build/DerivedData`

## Release App Output

The built Release app is left at:

- `build/DerivedData/Build/Products/Release/BugNarrator.app`

Use that path for extra manual checks if you want to inspect codesigning or bundle resources directly.

If you want to remove local build copies after testing so only `/Applications/BugNarrator.app` remains in Spotlight, Launch Services, and macOS privacy prompts, run:

```bash
./scripts/cleanup_local_build_apps.sh
```

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

The build scripts now pin the local macOS destination to the host architecture so the release path does not rely on Xcode's ambiguous default destination selection.

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

BugNarrator's canonical notarization identity is:

- Apple ID: `abdeffenderfer@icloud.com`
- Team ID: `2R4WAH4R53`
- Local keychain profile: `BugNarratorNotary`

Do not store the app-specific password in the repo. Keep it only in:

- 1Password item `Apple Notarytool - BugNarratorNotary`
- GitHub repository secret `APPLE_APP_SPECIFIC_PASSWORD`

If the password is rotated, update both of those locations before the next release.

First, store a notarization credential profile in your keychain:

```bash
xcrun notarytool store-credentials BugNarratorNotary \
  --apple-id abdeffenderfer@icloud.com \
  --team-id 2R4WAH4R53 \
  --password YOUR_APP_SPECIFIC_PASSWORD
```

Then build, notarize, staple, and validate in one command:

```bash
CODE_SIGNING_ALLOWED=YES \
CODE_SIGN_STYLE=Automatic \
CODE_SIGN_IDENTITY=\"Developer ID Application\" \
DEVELOPMENT_TEAM=2R4WAH4R53 \
ALLOW_PROVISIONING_UPDATES=YES \
NOTARIZE=YES \
NOTARY_PROFILE=BugNarratorNotary \
./scripts/build_dmg.sh
```

If app signing succeeds but Apple's notarization service is temporarily unavailable or blocked by an expired Apple Developer agreement, the script now reports that explicitly instead of looking like a signing failure. You still have two safe options:

- use `NOTARIZE=NO` for a signed-only internal build
- use `ALLOW_NOTARIZATION_FAILURE=YES` if you want the script to preserve the signed DMG and checksum files even when notarization fails

Example signed-only internal build:

```bash
CODE_SIGNING_ALLOWED=YES \
CODE_SIGN_IDENTITY="Developer ID Application" \
DEVELOPMENT_TEAM=2R4WAH4R53 \
NOTARIZE=NO \
./scripts/build_dmg.sh
```

Example "try notarization, but keep the signed artifact if Apple blocks notarization":

```bash
CODE_SIGNING_ALLOWED=YES \
CODE_SIGN_IDENTITY="Developer ID Application" \
DEVELOPMENT_TEAM=2R4WAH4R53 \
NOTARIZE=YES \
NOTARY_PROFILE=BugNarratorNotary \
ALLOW_NOTARIZATION_FAILURE=YES \
./scripts/build_dmg.sh
```

The packaging script will:

1. build the Release app
2. re-sign the app explicitly when a Developer ID build requires manual distribution signing
3. verify the app is signed
4. verify icon resources are present in the built app
5. create a styled DMG with `dmgbuild`
6. apply the custom volume icon and Finder window layout metadata directly
7. mount the DMG and verify `BugNarrator.app` plus the `Applications` shortcut are present
8. submit the DMG to Apple's notarization service
9. staple the notarization ticket to the DMG
10. run `stapler validate` and `spctl` checks

Because BugNarrator targets macOS 14 or later, the shipped app now uses ScreenCaptureKit for screenshot capture. No extra packaging step is required for that API, but your release smoke test should still verify that Screen Recording permission prompts only when the user requests a screenshot.

## Example Public Release Command

If your local Mac already has a `Developer ID Application` certificate and a `BugNarratorNotary` profile configured, this is the practical public-release command:

```bash
CODE_SIGNING_ALLOWED=YES \
CODE_SIGN_IDENTITY="Developer ID Application" \
DEVELOPMENT_TEAM=2R4WAH4R53 \
ALLOW_PROVISIONING_UPDATES=YES \
NOTARIZE=YES \
NOTARY_PROFILE=BugNarratorNotary \
./scripts/build_dmg.sh
```

That produces:

- `dist/BugNarrator-vX.Y.Z-macOS.dmg`
- `dist/BugNarrator-macOS.dmg`

## Releasing On GitHub

Recommended flow:

1. run `./scripts/release_smoke_test.sh`
2. run the signed/notarized packaging command
3. optionally run `./scripts/cleanup_local_build_apps.sh` after publishing so local test builds do not linger in `DerivedData`
4. create a GitHub Release
5. upload `dist/BugNarrator-macOS.dmg`
6. optionally upload the versioned `dist/BugNarrator-vX.Y.Z-macOS.dmg`
7. add release notes and link back to the changelog if needed
8. verify the README top download link matches the uploaded stable DMG filename
9. keep Apple signing credentials and the notary profile valid on the local release Mac before the next release

BugNarrator release builds are intentionally local-only. Do not rely on GitHub Actions to compile, sign, notarize, or package the macOS app.

## Verify The DMG

After building:

1. open the DMG in Finder
2. confirm the DMG window opens to a clean drag-to-Applications layout with `BugNarrator.app` on the left and `Applications` on the right
3. confirm the mounted DMG shows the branded BugNarrator volume icon on the desktop and in Finder
4. confirm `BugNarrator.app` is present
5. confirm the `Applications` shortcut is present
6. drag the app into `Applications`
7. confirm the installed app shows the branded BugNarrator icon in Finder
8. launch the installed app and verify first-run behavior

For a public release, also verify:

1. `xcrun stapler validate dist/BugNarrator-vX.Y.Z-macOS.dmg`
2. `spctl -a -vv build/DerivedData/Build/Products/Release/BugNarrator.app`
3. Gatekeeper accepts the downloaded DMG on a second Mac that has never built the app locally

Note: `spctl -a -vv -t open` against a locally produced DMG can report `Insufficient Context` on the build machine because the file is not a quarantined download. Treat `stapler validate` plus an app-level `spctl` check as the reliable local validation, then do a real download/open smoke test before publishing.

## Updating Release Links

The README intentionally points to:

- the stable direct asset path: `BugNarrator-macOS.dmg`
- the latest GitHub release page

If you change the stable DMG filename in the script, update the README download section in the same change so public visitors do not hit a broken link.

## Related Docs

- [README.md](../README.md)
- [Quickstart](../QUICKSTART.md)
- [Release Checklist](RELEASE_CHECKLIST.md)
