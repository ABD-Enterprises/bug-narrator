# BugNarrator User Guide

BugNarrator is a macOS menu bar app for narrated software testing sessions. It helps developers, testers, and product owners talk through a workflow, capture evidence, and turn that session into a transcript plus draft issues they can review or export.

BugNarrator intentionally runs as a single-instance app. If you open it again while it is already running, the existing instance should come forward and the second copy should exit. This avoids duplicate menu bar items and protects local session integrity.

## Getting Help

- [Download the latest macOS release](https://github.com/deffenda/bugnarrator/releases/latest)
- [Report a Bug](https://github.com/deffenda/bugnarrator/issues/new)
- [Request a Feature](https://github.com/deffenda/bugnarrator/issues/new)
- [Support Development](https://www.paypal.com/donate/?hosted_button_id=FWFQ6KCZBWWH8)

## What BugNarrator Is

BugNarrator is built for software walkthroughs and testing passes where you want to keep reviewing the target app instead of stopping to type notes.

It helps you:

- record narrated testing sessions
- create a transcript after the session ends
- attach screenshots to the review session and turn them into timeline markers automatically
- generate a review summary
- extract draft bugs, UX issues, enhancements, and follow-up questions
- export selected issues to GitHub Issues or Jira Cloud with experimental integrations
- browse and clean up old sessions from a session library

## Download And Installation

### Install From The DMG

1. Download the latest macOS release from [GitHub Releases](https://github.com/deffenda/bugnarrator/releases/latest).
2. Open the downloaded DMG.
3. Drag `BugNarrator.app` into `Applications`.
4. Launch BugNarrator from `Applications`.
5. If macOS shows a Gatekeeper warning, use Finder and choose `Open` for the app you trust.

### macOS Requirements

- macOS 14 or later
- microphone permission for recording
- Screen Recording permission if you want screenshot capture
- your own OpenAI API key for transcription and issue extraction

## First Run

1. Launch BugNarrator and confirm the menu bar icon appears.
2. Open `Settings`.
3. Paste your own `OpenAI API Key`.
4. Optionally click `Validate Key`.
5. Start a session with `Start Recording`.

BugNarrator does not ship with a built-in OpenAI API key. Transcription and issue extraction use your own OpenAI account and may incur charges under OpenAI pricing.

## Core Workflow

### Start A Narrated Testing Session

Start a session from the menu bar or by using your configured start hotkey if you assigned one. BugNarrator records in the background while you keep working in other apps. Starting a session opens a small recording controls window that stays available while you work.

The recording controls window includes:

- `Start Recording`
- `Stop Recording`
- `Capture Screenshot`

You can keep using global hotkeys if you assign them in Settings, but the recording controls window is the main control surface during a live review.

### Stop A Session

When you finish, stop the session from the control window or a stop hotkey you explicitly assigned. BugNarrator then uploads the recorded audio to OpenAI and waits for the transcript result.

### Review The Session

After transcription completes, BugNarrator opens the session library so you can inspect the transcript timeline, screenshots, review summary, and extracted issues in one place.

The intended mental model is:

`record → review → refine → export`

## Tester Narration Guide

Good sessions come from short, factual narration. BugNarrator can produce better transcripts, better bug summaries, cleaner repro steps, and better Codex or Claude follow-up prompts when the recording clearly states what you were testing, what you expected, and what actually happened. Unrelated chatter makes bug extraction harder.

Use this pattern during live testing:

1. Start with environment context.
   - `This is BugNarrator version [version] on macOS [version] on Apple Silicon. Installed from the DMG.`
   - `This is a fresh install.`
   - `This is an upgraded install over an older version.`
2. State the goal of the test.
   - `I'm testing first-launch microphone and screen recording permissions.`
   - `I'm testing that starting and stopping a recording creates a transcript and screenshot markers.`
3. Narrate each action as you do it.
   - `I'm clicking Start Recording now.`
   - `I'm opening Settings.`
   - `I'm stopping the session now.`
4. State the expected behavior before or during the action.
   - `I expected a macOS permission prompt here.`
   - `I expected the transcript to appear in the session library.`
5. State the actual behavior immediately when something is wrong.
   - `The prompt did not appear.`
   - `The session stopped, but no transcript was created.`
6. Call out system state when it matters.
   - `BugNarrator is not listed under Microphone in Privacy & Security.`
   - `The microphone toggle is already enabled.`
   - `I reopened BugNarrator after changing permissions.`
   - `I'm launching the app from Applications, not from Xcode.`
7. Mention timing or responsiveness when it is relevant.
   - `I waited ten seconds and no prompt appeared.`
   - `The window lost focus after I clicked Start Recording.`
   - `The spinner stayed visible for about twenty seconds.`
8. Use screenshot capture when something looks wrong, and say why.
   - `I'm taking a screenshot marker for the missing prompt.`
   - `I'm taking a screenshot marker for the disabled button state.`
9. End with a one- or two-sentence outcome summary.
   - `Ending test: recording started, but permissions were not granted correctly.`
   - `Ending test: transcript, screenshot, and summary all appeared as expected.`

### Word-For-Word Example

You can follow this script almost exactly:

- `This is BugNarrator version [version] on macOS [version] on Apple Silicon.`
- `I'm testing first-launch microphone and screen recording permissions.`
- `I'm clicking Start Recording now.`
- `I expected a macOS permission prompt here.`
- `The prompt did not appear.`
- `BugNarrator is not listed under Microphone in Privacy & Security.`
- `I'm taking a screenshot marker for the missing prompt.`
- `Ending test: recording started, but permissions were not granted correctly.`

### Do This / Avoid This

Do this:

- use short, factual sentences
- say one action at a time
- say what you expected and what actually happened
- mention version, install method, permissions state, or app location when they matter
- capture a screenshot when a visual problem or missing prompt is important

Avoid this:

- unrelated chatter or side conversations
- long theories while the problem is still happening
- vague comments like `it broke` without describing what broke
- mixing multiple issues into one sentence
- waiting until the end of the session to describe the main failure

## Core Features

### Recording Narrated Testing Sessions

Recording is designed for real software review work. You can switch apps, click, type, and navigate normally while the microphone session continues in the background.

### Transcript Generation

BugNarrator generates the transcript only after the session ends. It does not try to type live dictation into the active app.

### Screenshot Capture

Use screenshot capture to save visual evidence during a review. On macOS 14 and later, BugNarrator uses ScreenCaptureKit plus a drag-selection overlay that works like a lightweight macOS capture tool. Press `Capture Screenshot`, drag across the area you want, release to save it, or press `Esc` to cancel. Each screenshot is attached to the current session, automatically creates a timeline marker at the same timestamp, and appears in the `Screenshots` tab with a thumbnail, timestamp, and linked marker when available.

### Review Summary

The summary view gives you a quick understanding of what the session covered before you read the full transcript.

### Issue Extraction

Issue extraction creates reviewable draft issues in categories such as:

- Bug
- UX Issue
- Enhancement
- Question / Follow-up

Each extracted item keeps evidence from the transcript and should be reviewed before export.

### Export Session Bundle

Use this when you want a portable local copy of the session. The bundle can include:

- `transcript.txt`
- `transcript.md`
- `summary.md`
- `screenshots/`

### Export To GitHub (Experimental)

After you configure your GitHub token, repository owner, and repository name in Settings, you can export selected extracted issues as GitHub Issues. This integration is currently experimental.

### Export To Jira (Experimental)

After you configure your Jira Cloud URL, email, API token, project key, and issue type in Settings, you can export selected extracted issues as Jira issues. This integration is currently experimental.

### Copy Debug Info

Use `Copy Debug Info` from the menu bar or Settings when you need a quick support summary. It copies:

- BugNarrator version
- macOS version
- device architecture
- active transcription model
- active issue extraction model
- log level
- current session ID when available

### Export Debug Bundle

Use `Export Debug Bundle` when you need a fuller support package for a GitHub issue. The bundle includes:

- `system-info.json`
- `app-version.txt`
- `macos-version.txt`
- `recent-log.txt`
- `session-metadata.json`

The bundle is local-only and intentionally excludes API keys, GitHub tokens, Jira tokens, and other raw credentials.

## Session Library

The session library is the main place to revisit earlier work.

You can:

- browse `Today`, `Yesterday`, `Last 7 Days`, `Last 30 Days`, or `All Sessions`
- use a custom date range
- search transcript text, titles, and summaries
- sort by newest first or oldest first
- open a detail pane with the transcript timeline, screenshots, summary, and extracted issues
- delete sessions you no longer need

BugNarrator keeps lightweight session-library metadata in memory so bigger histories remain more responsive when you switch filters, search, sort, or jump between sessions quickly.

Treat the session library as an archive of review sessions rather than a plain transcript list. It is where you compare evidence, refine extracted issues, and decide what should be exported.

The right-hand review workspace is organized around clear tabs so you can move between:

- Transcript
- Screenshots
- Extracted Issues
- Review Summary

Older sessions that already contain standalone markers still render safely in the transcript timeline and exports.

Deleting a session removes it from the library immediately and also removes local screenshot files that BugNarrator manages for that session. Exported files outside the app are not deleted.

## Support Development

BugNarrator is free to use. Donations are optional and separate from any OpenAI costs.

- [Open the PayPal support page](https://www.paypal.com/donate/?hosted_button_id=FWFQ6KCZBWWH8)

## Reporting A Bug

If you need help with a problem:

1. Reproduce the issue if you can.
2. Use `Copy Debug Info` and paste the result into your GitHub issue.
3. Use `Export Debug Bundle` and attach the bundle.
4. If the problem affects a specific session, attach an exported session bundle or relevant screenshots too.

BugNarrator keeps diagnostics local until you explicitly export or copy them for support.

## Troubleshooting

### No Transcript Generated

- confirm your OpenAI API key is configured in `Settings`
- validate the key if needed
- confirm the Mac has network access
- retry with a short test recording to rule out an empty or corrupt audio file

### Microphone Permission Problems

- use BugNarrator's `Open Microphone Settings` button if it appears in the menu bar window
- or open `System Settings > Privacy & Security > Microphone`
- verify microphone permission is granted to BugNarrator
- if BugNarrator says microphone access is restricted, also check device-management, parental-control, or workplace policy restrictions
- if BugNarrator says audio capture is unavailable even though permission is enabled, check that an input device is connected and not already failing at the macOS level
- if you are testing from Xcode or `DerivedData`, keep launching the same local app copy or switch to the signed DMG build; macOS may treat different local build paths as different apps for microphone approval
- restart the app after changing permission settings if needed

### BugNarrator Opened Twice

- BugNarrator is designed to allow only one running instance
- if you try to launch a second copy, the existing instance should become active and the new copy should exit
- if you see two BugNarrator menu bar items at once, quit both copies and relaunch the copy in `Applications`

### API Key Missing

- open `Settings`
- paste your own OpenAI API key
- click `Validate Key` if you want to check it before transcription or issue extraction
- BugNarrator stores the key in macOS Keychain when available

### API Key Rejected Or Revoked

- open `Settings`
- replace the key or remove it and paste a new one
- click `Validate Key`
- try the session again after OpenAI accepts the new key

### Screenshots Not Appearing

- confirm the session was actively recording when the screenshot was requested
- after pressing `Capture Screenshot`, drag to select a real on-screen region before releasing the mouse
- press `Esc` if you want to cancel the selection without saving anything; BugNarrator keeps recording and shows a lightweight cancellation message instead of a blocking error
- use BugNarrator's `Open Screen Recording Settings` button if it appears in the menu bar window
- or open `System Settings > Privacy & Security > Screen & System Audio Recording`
- confirm Screen Recording permission is granted if macOS prompted for it
- remember that this permission is only needed for screenshots; audio recording and transcription can still continue without it
- remember that audio recording can continue even if screenshots are unavailable
- try another screenshot to rule out a temporary storage failure

### Export Errors

- for GitHub, verify the token, repository owner, and repository name
- for Jira, verify the base URL, email, API token, project key, and issue type
- confirm your Mac still has network access

## Privacy

What stays local on your Mac:

- saved session history
- screenshot-driven timeline markers and older marker data from existing sessions
- screenshots and screenshot metadata
- extracted issue drafts
- exported session bundles

What is sent to OpenAI:

- recorded audio after you stop a session and request transcription
- transcript context used for review summary or issue extraction

BugNarrator does not continuously stream live audio to OpenAI while you are still recording.

## More Documentation

- [Quickstart](../QUICKSTART.md)
- [Distribution and DMG packaging](Distribution.md)
- [Security Notes](../SECURITY.md)
- [Project Changelog](../CHANGELOG.md)
