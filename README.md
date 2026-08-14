# BugNarrator

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14%2B-black)](https://www.apple.com/macos/)

BugNarrator is a macOS menu bar tool for narrated software testing sessions that automatically captures transcripts, screenshot-based timeline markers, screenshots, and extracted issues.

BugNarrator intentionally runs as a single-instance menu bar app. If you launch it again while it is already running, the existing instance is reactivated and the second copy exits so you do not end up with duplicate menu bar items or competing session state.

## Download BugNarrator

- [Download the latest macOS DMG](https://github.com/ABD-Enterprises/bug-narrator/releases/latest/download/BugNarrator-macOS.dmg)
- [View the latest release page](https://github.com/ABD-Enterprises/bug-narrator/releases/latest)

If the direct DMG link is not live yet, use the release page and download the newest `BugNarrator-macOS.dmg` or `BugNarrator-vX.Y.Z-macOS.dmg` asset there.

## Support Development

BugNarrator is free to use. If it helps your workflow, consider supporting development.

- [Support BugNarrator on PayPal](https://www.paypal.com/donate/?hosted_button_id=FWFQ6KCZBWWH8)

## Help And Project Links

- [Read the user manual](docs/user/user-manual.md)
- [Canonical product spec](docs/architecture/product-spec.md)
- [Getting started for maintainers and testers](docs/onboarding/getting-started.md)
- [Release process](docs/release/release-process.md)
- [Roadmap history and completed phases](docs/roadmap/roadmap.md)
- [GitHub issues and active work](https://github.com/ABD-Enterprises/bug-narrator/issues)
- [Detailed user guide](docs/UserGuide.md)
- [Tester narration guide](docs/UserGuide.md#tester-narration-guide)
- [Hosted documentation](https://github.com/ABD-Enterprises/bug-narrator/blob/main/docs/UserGuide.md)
- [Report a bug or request a feature](https://github.com/ABD-Enterprises/bug-narrator/issues/new)
- [View the changelog](CHANGELOG.md)

## What BugNarrator Does

The canonical product contract lives in [docs/architecture/product-spec.md](docs/architecture/product-spec.md). Use that spec for behavior, terminology, artifact contracts, and cross-platform parity expectations.

BugNarrator is built for software-review and software-testing workflows where you want to keep clicking through an app while speaking your notes out loud.

The product is organized around one durable workflow:

`record → review → refine → export`

It can:

- record a narrated session from the menu bar
- transcribe the finished recording with the configured AI provider
- capture screenshots during a live review and turn them into timeline markers automatically
- generate a review summary
- extract draft bugs, UX issues, enhancements, and follow-up questions
- export selected issues to GitHub Issues or Jira Cloud with experimental integrations
- export a local session bundle with transcript and screenshot artifacts
- keep a searchable session library with date filters and deletion (the 500 most recent sessions are retained; older ones are removed along with their screenshots and audio, and BugNarrator tells you when that happens)
- stay responsive with larger local histories by caching session-library metadata for faster filtering, search, and selection changes

## Bring Your Own AI Provider

BugNarrator does not ship with built-in AI access or credits.

OpenAI is the hosted default provider. In `Settings`, you can also choose `OpenAI-Compatible`, `Local-Compatible`, or `Local (Parakeet)`.

Important:

- `OpenAI` requires your own OpenAI API key and uses `https://api.openai.com` unless you override it
- `OpenAI-Compatible` is for enterprise gateways or hosted providers that expose compatible transcription and chat endpoints
- `Local-Compatible` is for local or self-hosted OpenAI-compatible endpoints such as LM Studio or Ollama
- `Local (Parakeet)` transcribes on this Mac through the local server at `http://localhost:8422`, does not use an API key, and does not upload audio

#### Installing the local Parakeet server

The server ships as a signed, notarized download — no source checkout, no
Python, no build step:

1. Download `bugnarrator-transcription-macos-arm64.dmg` from the
   [latest release](https://github.com/ABD-Enterprises/bug-narrator/releases/latest),
   and verify it against the published `.sha256` if you want to.
2. Open the disk image, copy `bugnarrator-transcription` to a local folder, and
   run it in Terminal:

```bash
./bugnarrator-transcription --preload
```

3. In BugNarrator, choose `Local (Parakeet)`. It uses `http://localhost:8422`
   automatically and needs no API key.

Leave that Terminal window running while you record. Apple Silicon only; the
first `--preload` downloads the speech model. Long recordings are processed in
bounded local chunks and can take several minutes; BugNarrator waits for the
active local inference instead of starting duplicate retries.

- transcription requires a provider endpoint compatible with `/v1/audio/transcriptions`
- review summary and issue extraction require a provider endpoint compatible with `/v1/chat/completions`
- unsupported provider/model combinations show clear setup guidance in Settings instead of starting a broken transcription
- provider usage may cost money on your account when you use a hosted provider
- the app stores your provider credential in macOS Keychain when available
- credentials are not bundled into the source code or compiled app
- global hotkeys are optional and start unassigned until you assign them

## Install On macOS

1. Download the latest DMG from [GitHub Releases](https://github.com/ABD-Enterprises/bug-narrator/releases/latest).
2. Open the DMG. It should present a drag-to-Applications install window.
3. Drag `BugNarrator.app` into `Applications`.
4. Launch BugNarrator from `Applications`.
5. On first run, expect AI provider setup. Microphone permission is requested the first time you try to start recording.
6. If you use screenshot capture, expect Screen Recording permission on first use.
7. If a permission is denied, use the recovery buttons in the menu bar window to reopen the correct System Settings pane.
8. If you try to launch BugNarrator a second time, macOS should bring the existing BugNarrator instance forward instead of opening another menu bar copy.

BugNarrator releases are signed with a `Developer ID Application` certificate (Team ID `2R4WAH4R53`), notarized by Apple, and stapled, so macOS will not show the "unidentified developer" warning. A first launch of any downloaded app still shows the standard one-time "downloaded from the Internet" confirmation. If macOS reports an unidentified developer, do not bypass it — verify the DMG against the published `.sha256` checksum and report it.

## Quick Start

1. Launch BugNarrator and open the menu bar item.
2. Open `Settings`.
3. Choose an AI provider. Use `OpenAI` for hosted transcription and issue extraction, or `Local (Parakeet)` for local transcription after the local Parakeet server is installed and running.
4. Optionally click `Validate Key` or `Validate Connection`.
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
- search across full transcript text, titles, summaries, marker notes, and extracted issues
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

### Backups and moving to another Mac

Session bodies and the search index are encrypted with a key kept in your login
Keychain as *this-device-only*. Screenshots and recorded audio are **not**
encrypted — see [SECURITY.md](SECURITY.md) for exactly what is and is not
covered, and why. That is deliberate — it means a copy of the files alone is
useless to anyone else — but it has a consequence worth knowing before you need
it: **a Time Machine restore, a Migration Assistant move, or a dead machine
leaves the encrypted library unreadable.** The files come back; the key does not.

The escape hatch is **Settings > Diagnostics & Privacy > Export Data**, which
writes your sessions as plain JSON that does not depend on that key. Run it
before you migrate or retire a Mac. Treat the export accordingly — it is
readable by anything that can read the file.

Data that stays local on your Mac:

- session history
- transcripts after they return from the configured AI provider
- screenshot-driven timeline markers and older marker data from existing sessions
- screenshot image files, unless you opt in to uploading them (see the next list)
- extracted issue drafts
- exported bundles you explicitly create

Data sent to the configured AI provider:

- recorded audio when you stop a session and request transcription
- transcript context used for issue extraction or summary generation
- screenshot **filenames and timestamps** during issue extraction, so the model can tie narration to a capture
- the screenshot **images themselves**, but only if you turn on Settings > Diagnostics & Privacy > "Send screenshots to the AI provider". This is off by default.
- when duplicate review is enabled, the titles and summaries of candidate issues fetched from your configured GitHub or Jira tracker

Issue extraction is shaped to what the provider can accept. Hosted providers (OpenAI, OpenAI-Compatible) get JSON response mode, plus screenshot images if you opted in, with a 60-second budget. The Local-Compatible provider gets neither — most local models reject `image_url` parts and `response_format: json_object` outright — and gets 120 seconds, because a local model being slow is not a failure.

BugNarrator does not continuously upload audio while you are still recording.

"Check for Updates" reads BugNarrator's public GitHub releases feed to see whether a newer version exists. The request is unauthenticated and carries no identifiers — nothing about you or your install is sent, and it happens only when you click it.

BugNarrator sends no telemetry off your Mac. There is no remote log collection, no analytics service, and no crash reporter.

It does keep a local-only operational log at `~/Library/Application Support/BugNarrator/operational-telemetry.jsonl`, recording named events such as recordings started, transcriptions completed, app errors, and unclean-exit detection. That file stays on disk and is never transmitted; it is read only when you explicitly copy debug info, export a debug bundle, or run Export Data. Turn it off with **Settings > Diagnostics & Privacy > "Record local usage analytics"**, and delete the file at any time.

Transcripts are **not** copied to the clipboard unless you ask. **Settings > General > "Auto-copy transcript to clipboard"** is off by default; turning it on puts the full transcript on the system pasteboard every time a session is saved, where clipboard managers may retain it.

## Reporting Problems

If you need help or want to file a GitHub issue:

1. Open BugNarrator and reproduce the problem.
2. Hold `Option` while the menu bar window is open to reveal `Export Debug Bundle`.
3. Export a safe local diagnostics bundle.
4. Attach the debug bundle and, if relevant, a session bundle or screenshots.

The debug bundle includes version info, macOS info, recent local logs, and safe session metadata. It does not include API keys, GitHub tokens, Jira tokens, or other raw credentials.

## Download, Help, And Support Links

- [Latest macOS release page](https://github.com/ABD-Enterprises/bug-narrator/releases/latest)
- [User documentation](docs/UserGuide.md)
- [Hosted user guide](https://github.com/ABD-Enterprises/bug-narrator/blob/main/docs/UserGuide.md)
- [Report a bug or request a feature](https://github.com/ABD-Enterprises/bug-narrator/issues/new)
- [Support development](https://www.paypal.com/donate/?hosted_button_id=FWFQ6KCZBWWH8)
- [Changelog](CHANGELOG.md)
- [GitHub issues](https://github.com/ABD-Enterprises/bug-narrator/issues)

## Build From Source

For the structured maintainer setup guide, see [docs/development/setup.md](docs/development/setup.md).

Before opening a PR or spending CI runner time, run the cheap local-first validation entry point:

```bash
./scripts/validate.sh origin/main
```

That command mirrors the portable CI guardrails: changed-file Semgrep when available, Swift parse checks, local-transcription syntax checks, repository docs drift checks, and effort-leak issue/PR state checks.

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
- [SECURITY.md](SECURITY.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)

## Known Limitations

- hosted transcription, review summary, issue extraction, GitHub export, and Jira export require network access
- `Local (Parakeet)` is transcription-only; review summary and issue extraction still require an OpenAI-compatible chat provider
- GitHub and Jira export include screenshot references in issue bodies instead of uploading attachments automatically
- session deletion is permanent today

## Contribution Policy

BugNarrator is not currently accepting outside code contributions or pull requests.

Bug reports and focused feature requests are still welcome through [GitHub Issues](https://github.com/ABD-Enterprises/bug-narrator/issues/new). See [CONTRIBUTING.md](CONTRIBUTING.md) for the current policy.

## License

BugNarrator is licensed under the Apache License 2.0.

This license allows users to freely use, modify, and distribute the software, including for commercial purposes, as long as attribution and license terms are preserved.

See the [LICENSE](LICENSE) file for details.
