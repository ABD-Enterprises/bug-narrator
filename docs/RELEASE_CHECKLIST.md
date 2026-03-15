# BugNarrator Release Checklist

Use this checklist before cutting a public test build or release candidate.

## Build And Signing

- Regenerate the project with `xcodegen generate` if `project.yml` changed.
- Run `./scripts/release_smoke_test.sh` and confirm it passes before packaging a candidate build.
- Build the app in the intended configuration and confirm the build succeeds.
- Run `./scripts/build_dmg.sh` and confirm the DMG packaging step succeeds.
- If shipping a signed build, verify the Apple signing team, bundle identifier, and entitlements are correct.
- For a public download, use `Developer ID Application` signing rather than `Apple Development`.
- If publishing broadly, notarize the DMG and staple the ticket before release.
- Confirm the Release app bundle contains `Contents/Resources/AppIcon.icns` and `Contents/Resources/Assets.car`.
- Confirm the signed Release app and the mounted DMG app both retain `com.apple.security.device.audio-input=true`.
- Launch the built app and confirm the menu bar item appears.
- Confirm first launch does not trigger an unexpected Keychain prompt before the user opens Settings or starts a credential-dependent workflow.

## Core Product Workflow

- Add or validate an OpenAI API key in Settings.
- Start a recording session and confirm the app enters `Recording`.
- Capture at least one screenshot during the session and confirm it creates a visible timeline moment in review.
- Stop the session and confirm transcription succeeds.
- Confirm the transcript, review summary, screenshots, and extracted issues appear in the session library.
- Export a session bundle and verify the expected files are created.

## Export Integrations

- Verify GitHub export stays disabled until configuration is complete.
- Export at least one issue to GitHub with a working repository/token pair.
- Verify Jira export stays disabled until configuration is complete.
- Export at least one issue to Jira Cloud with a working project/token pair.
- Exercise at least one invalid-config or invalid-auth path for each provider and confirm the error message is clear.

## Heavy-Use Library Checks

- Confirm `Today`, `Yesterday`, `Last 7 Days`, `Last 30 Days`, and `All Sessions` all behave correctly.
- Use a custom date range and confirm the session list updates immediately.
- Search by transcript text or summary text and confirm results narrow correctly.
- Delete a session and confirm the list, counts, and detail pane update immediately.
- Switch from a session with extracted issues or summary content to one without those sections and confirm the review workspace falls back to a valid tab instead of showing stale content.
- Open a screenshot-heavy session and confirm the `Screenshots` tab stays responsive while loading previews.

## Artifact And Persistence Safety

- Quit and relaunch the app and confirm existing sessions reload correctly.
- If local history storage fails after a successful transcription, confirm the transcript still opens as an unsaved session and can be saved later after storage is restored.
- Delete a session with screenshots and verify the local managed screenshot folder is removed.
- Confirm exported bundles outside the app remain untouched after deletion.
- In non-debug mode, verify temporary audio files are cleaned up after success, failure, and cancellation.
- In debug mode, verify temporary audio files are retained intentionally.

## Product Surfaces

- Open `About BugNarrator` and verify version/build info is correct.
- Open `View Documentation`, `Report an Issue`, `Support Development`, `What's New`, and `Check for Updates`.
- Confirm every link opens the expected external destination.
- Review the README, user guide, changelog, and support links for stale wording or placeholder text.
- Review the `Download` and `Support Development` sections in `README.md` for visibility and accuracy.
- Confirm the top-of-README quick links for documentation, issue reporting, and support all work.
- Delete a session from the library and confirm stale GitHub or Jira export actions are not still available for that removed selection.

## Before Publishing

- Confirm no secrets, tokens, personal paths, or local-only files are tracked in git.
- Review `.gitignore` for generated Xcode data and result bundles.
- Upload `dist/BugNarrator-macOS.dmg` to the release and confirm the release asset name matches the README link strategy.
- If you built or tested BugNarrator from local `DerivedData`, run `./scripts/cleanup_local_build_apps.sh` after publishing so only the installed `/Applications` copy remains in normal tester paths.
- Open the final DMG and confirm Finder shows the branded BugNarrator icon instead of the generic macOS app placeholder.
- Confirm the DMG contains `BugNarrator.app` plus the `Applications` shortcut and supports the normal drag-to-Applications install flow.
- Run `xcrun stapler validate` on the final DMG.
- Run `spctl -a -vv build/DerivedData/Build/Products/Release/BugNarrator.app` and confirm the notarized app is accepted.
- If `spctl -a -vv -t open` on the local DMG reports `Insufficient Context`, treat that as a local-check limitation and verify the published download on a second Mac instead.
- Run the automated test suite and confirm it passes.
- Run the automated test suite with no manually launched BugNarrator copies required, and confirm single-instance enforcement does not interfere with the XCTest app host.
- Note any known limitations in the release notes or changelog before publishing.
