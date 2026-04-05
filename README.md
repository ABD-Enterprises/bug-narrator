# BugNarrator

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14%2B-black)](https://www.apple.com/macos/)

BugNarrator is a macOS menu bar tool for narrated software testing sessions that automatically captures transcripts, screenshot-based timeline markers, screenshots, and extracted issues.

BugNarrator intentionally runs as a single-instance menu bar app. If you launch it again while it is already running, the existing instance is reactivated and the second copy exits so you do not end up with duplicate menu bar items or competing session state.

## Download BugNarrator

- [Download the latest macOS DMG](https://github.com/deffenda/bugnarrator/releases/latest/download/BugNarrator-macOS.dmg)
- [View the latest release page](https://github.com/deffenda/bugnarrator/releases/latest)

If the direct DMG link is not live yet, use the release page and download the newest `BugNarrator-macOS.dmg` or `BugNarrator-vX.Y.Z-macOS.dmg` asset there.

## Support Development

BugNarrator is free to use. If it helps your workflow, consider supporting development.

- [Support BugNarrator on PayPal](https://www.paypal.com/donate/?hosted_button_id=FWFQ6KCZBWWH8)

## Help And Project Links

- AI-assisted work starts at [ai/bootstrap.md](ai/bootstrap.md)
- [Read the user manual](docs/user/user-manual.md)
- [Canonical product spec](docs/architecture/product-spec.md)
- [Getting started for maintainers and testers](docs/onboarding/getting-started.md)
- [Release process](docs/release/release-process.md)
- [Roadmap and planned phases](docs/roadmap/roadmap.md)
- [Detailed user guide](docs/UserGuide.md)
- [Tester narration guide](docs/UserGuide.md#tester-narration-guide)
- [Hosted documentation](https://github.com/deffenda/bugnarrator/blob/main/docs/UserGuide.md)
- [Report a bug or request a feature](https://github.com/deffenda/bugnarrator/issues/new)
- [View the changelog](CHANGELOG.md)

## What BugNarrator Does

The canonical product contract lives in [docs/architecture/product-spec.md](docs/architecture/product-spec.md). Use that spec for behavior, terminology, artifact contracts, and cross-platform parity expectations.

BugNarrator is built for software-review and software-testing workflows where you want to keep clicking through an app while speaking your notes out loud.

The product is organized around one durable workflow:

`record → review → refine → export`

It can:

- record a narrated session from the menu bar
- transcribe the finished recording with the OpenAI API
- capture screenshots during a live review and turn them into timeline markers automatically
- generate a review summary
- extract draft bugs, UX issues, enhancements, and follow-up questions
- export selected issues to GitHub Issues or Jira Cloud with experimental integrations
- export a local session bundle with transcript and screenshot artifacts
- keep a searchable session library with date filters and deletion
- stay responsive with larger local histories by caching session-library metadata for faster filtering, search, and selection changes

## Bring Your Own OpenAI API Key

BugNarrator does not ship with a built-in OpenAI API key.

Every user must provide their own key in `Settings` before transcription or issue extraction will work.

Important:

- transcription uses the OpenAI API, not a local Whisper model
- issue extraction also uses the OpenAI API
- OpenAI usage may cost money on your account
- the app stores your key in macOS Keychain when available
- the key is not bundled into the source code or compiled app
- global hotkeys are optional and start unassigned until you assign them

## Install On macOS

1. Download the latest DMG from [GitHub Releases](https://github.com/deffenda/bugnarrator/releases/latest).
2. Open the DMG. It should present a drag-to-Applications install window.
3. Drag `BugNarrator.app` into `Applications`.
4. Launch BugNarrator from `Applications`.
5. If Gatekeeper warns about the app, open `Applications`, Control-click `BugNarrator.app`, choose `Open`, then confirm once.
6. On first run, expect OpenAI API key setup. Microphone permission is requested the first time you try to start recording.
7. If you use screenshot capture, expect Screen Recording permission on first use.
8. If a permission is denied, use the recovery buttons in the menu bar window to reopen the correct System Settings pane.
9. If you try to launch BugNarrator a second time, macOS should bring the existing BugNarrator instance forward instead of opening another menu bar copy.

## Quick Start

1. Launch BugNarrator and open the menu bar item.
2. Open `Settings`.
3. Paste your own `OpenAI API Key`.
4. Optionally click `Validate Key`.
5. Click `Show Recording Controls`.
6. Click `Start Recording`.
7. Speak while you continue reviewing the target app. For better transcripts and bug reports, follow the [Tester Narration Guide](docs/UserGuide.md#tester-narration-guide).
8. Keep the recording controls window available while you review. Use it, or any global hotkeys you explicitly assign in Settings, to stop recording and capture screenshots without reopening the menu.
9. Click `Stop Recording`.
10. Review the transcript, summary, screenshots, and extracted issues in the session library.
11. Export a session bundle or selected issues when needed.

## Session Workflow

### Recording

BugNarrator records in the background while you switch apps and continue normal mouse or keyboard interaction. It does not type live dictation into the frontmost app.

Click `Show Recording Controls` from the menu bar to open the persistent recording controls window. That window is the primary place to:

- start the session
- stop the session
- capture screenshots

It stays open until you close it, even after recording stops, so you can reuse the same control surface across repeated sessions.

### Screenshot Capture

Screenshots are captured only when you request them. On macOS 14 and later, BugNarrator uses ScreenCaptureKit and a drag-to-select overlay so you can choose the exact region you want to capture instead of saving every display. Each screenshot is attached to the current session, creates an automatic timeline marker at the same timestamp, and appears later in the `Screenshots` tab with a thumbnail, timestamp, and linked marker label when available.

### Review Summary

The review summary gives you a compact pass over the session before you read the full transcript.

### Issue Extraction

BugNarrator can turn the session transcript into draft review items in categories such as:

- Bug
- UX Issue
- Enhancement
- Question / Follow-up

These are drafts. Review them before export.

### Session Library

The session library is designed for repeated daily use and supports:

- `Today`, `Yesterday`, `Last 7 Days`, `Last 30 Days`, `All Sessions`, and `Custom Date Range`
- search across transcript text, titles, and summaries
- newest-first or oldest-first sorting
- inline detail review with a clearer workspace for the transcript timeline, screenshots, review summary, and extracted issues
- permanent deletion of sessions you no longer want to keep
- cached metadata and lookup indexes so larger local histories stay more responsive than a full eager transcript scan

Think of the session library as your review archive, not just a transcript list. It is where you revisit sessions, compare evidence, refine extracted issues, and decide what to export.

## Export Options

### Export Session Bundle

Use `Export Session Bundle` when you want a local package of the review session. The bundle includes:

- `transcript.md`
- `screenshots/`

### Export To GitHub (Experimental)

Configure your GitHub token, repository owner, and repository name in Settings, then export selected extracted issues as GitHub Issues. This integration is currently experimental.

### Export To Jira (Experimental)

Configure your Jira Cloud URL, email, API token, project key, and issue type in Settings, then export selected extracted issues as Jira issues. This integration is currently experimental.

## Permissions

### Microphone

BugNarrator now runs a microphone preflight before recording starts. It requests permission only when needed, blocks recording before any fake recording state appears, and distinguishes between:

- access not granted yet
- access denied
- access restricted
- audio capture unavailable even though permission looks enabled

If access is denied, recording is blocked until you re-enable BugNarrator in `System Settings > Privacy & Security > Microphone`. If access is restricted, the app tells you to check device-management or parental-control restrictions. If permission looks granted but audio capture still cannot be prepared, BugNarrator reports that as a microphone availability problem instead of a generic recording failure.

For local testing from Xcode or `DerivedData`, macOS may treat different app bundle paths as different apps. If microphone behavior looks inconsistent while testing unsigned builds, keep launching the same local app copy or use the signed DMG build for steadier permission behavior.

### Screen Recording

Screenshot capture may prompt for Screen Recording permission on first use. That permission is only needed for screenshots. If access is denied, the current recording can still continue without screenshots, and the menu bar window includes an `Open Screen Recording Settings` recovery button. Press `Capture Screenshot`, drag to select the region you want, release to save it, or press `Esc` to cancel cleanly without interrupting recording.

### Accessibility

BugNarrator does not require Accessibility permission for its core workflow because it does not simulate typing into other apps.

## Privacy And Data Handling

Data that stays local on your Mac:

- session history
- transcripts after they return from OpenAI
- screenshot-driven timeline markers and older marker data from existing sessions
- screenshots and screenshot metadata
- extracted issue drafts
- exported bundles you explicitly create

Data sent to OpenAI:

- recorded audio when you stop a session and request transcription
- transcript context used for issue extraction or summary generation

BugNarrator does not continuously upload audio while you are still recording.

BugNarrator does not include automatic telemetry or remote log collection. Diagnostics stay local on your Mac until you explicitly copy debug info or export a debug bundle for support.

## Reporting Problems

If you need help or want to file a GitHub issue:

1. Open BugNarrator and reproduce the problem.
2. Hold `Option` while the menu bar window is open to reveal `Export Debug Bundle`.
3. Export a safe local diagnostics bundle.
4. Attach the debug bundle and, if relevant, a session bundle or screenshots.

The debug bundle includes version info, macOS info, recent local logs, and safe session metadata. It does not include API keys, GitHub tokens, Jira tokens, or other raw credentials.

## Download, Help, And Support Links

- [Latest macOS release page](https://github.com/deffenda/bugnarrator/releases/latest)
- [User documentation](docs/UserGuide.md)
- [Hosted user guide](https://github.com/deffenda/bugnarrator/blob/main/docs/UserGuide.md)
- [Report a bug or request a feature](https://github.com/deffenda/bugnarrator/issues/new)
- [Support development](https://www.paypal.com/donate/?hosted_button_id=FWFQ6KCZBWWH8)
- [Changelog](CHANGELOG.md)
- [Post-1.0.0 bug log](docs/PostV1BugLog.md)

## Build From Source

For the structured maintainer setup guide, see [docs/development/setup.md](docs/development/setup.md).

Open `BugNarrator.xcodeproj` in Xcode and build the `BugNarrator` scheme, or use:

```bash
xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Run tests with:

```bash
xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO test
```

## Build The DMG

For the canonical structured release and deployment docs, see:

- [docs/operations/deployment.md](docs/operations/deployment.md)
- [docs/release/release-process.md](docs/release/release-process.md)

BugNarrator includes a repeatable local packaging script:

```bash
./scripts/build_dmg.sh
```

The script builds a Release app, creates a DMG with `BugNarrator.app` plus an `Applications` shortcut, and writes artifacts to `dist/`.

Full packaging details live in [docs/Distribution.md](docs/Distribution.md).

For public distribution, use a `Developer ID Application` certificate plus notarization so Gatekeeper accepts the download on other Macs. The packaging script supports:

- unsigned local packaging for development
- signed Release builds
- notarization and stapling
- validation that the DMG contains `BugNarrator.app`, an `Applications` shortcut, and the expected branded icon resources

## Documentation

- [QUICKSTART.md](QUICKSTART.md)
- [docs/UserGuide.md](docs/UserGuide.md)
- [docs/Distribution.md](docs/Distribution.md)
- [docs/QA_CHECKLIST.md](docs/QA_CHECKLIST.md)
- [docs/TESTING_NOTES.md](docs/TESTING_NOTES.md)
- [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md)
- [docs/PostV1BugLog.md](docs/PostV1BugLog.md)
- [SECURITY.md](SECURITY.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)

## Known Limitations

- transcription and issue extraction require network access
- BugNarrator does not yet support offline Whisper
- GitHub and Jira export include screenshot references in issue bodies instead of uploading attachments automatically
- session deletion is permanent today

## Contribution Policy

BugNarrator is not currently accepting outside code contributions or pull requests.

Bug reports and focused feature requests are still welcome through [GitHub Issues](https://github.com/deffenda/bugnarrator/issues/new). See [CONTRIBUTING.md](CONTRIBUTING.md) for the current policy.

## License

BugNarrator is licensed under the Apache License 2.0.

This license allows users to freely use, modify, and distribute the software, including for commercial purposes, as long as attribution and license terms are preserved.

See the [LICENSE](LICENSE) file for details.
