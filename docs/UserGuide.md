# BugNarrator User Guide

BugNarrator is a macOS menu bar app for narrated software testing sessions. It helps developers, testers, and product owners talk through a workflow, capture evidence, and turn that session into a transcript plus draft issues they can review or export.

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
- mark important moments with timeline markers
- attach screenshots to the review session
- generate a review summary
- extract draft bugs, UX issues, enhancements, and follow-up questions
- export selected issues to GitHub Issues or Jira Cloud
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
5. Start a session with `Start Feedback Session`.

BugNarrator does not ship with a built-in OpenAI API key. Transcription and issue extraction use your own OpenAI account and may incur charges under OpenAI pricing.

## Core Workflow

### Start A Narrated Testing Session

Start a session from the menu bar or by using your configured recording hotkey. BugNarrator records in the background while you keep working in other apps. During recording, the preferred workflow is to keep using the global hotkeys or the floating recording HUD instead of reopening the menu.

### Stop A Session

When you finish, stop the session from the menu bar or hotkey. BugNarrator then uploads the recorded audio to OpenAI and waits for the transcript result.

### Review The Session

After transcription completes, BugNarrator opens the session library so you can inspect the transcript, markers, screenshots, summary, and extracted issues in one place.

## Core Features

### Recording Narrated Testing Sessions

Recording is designed for real software review work. You can switch apps, click, type, and navigate normally while the microphone session continues in the background.

### Transcript Generation

BugNarrator generates the transcript only after the session ends. It does not try to type live dictation into the active app.

### Markers

Markers let you flag moments that matter while the session is still running. They help you jump to specific points in the transcript later and appear in transcript exports.

### Screenshot Capture

Use screenshot capture to save visual evidence during a review. On macOS 14 and later, BugNarrator uses ScreenCaptureKit for this capture path. Each screenshot is attached to the current session and automatically inserts a marker at the same timestamp so the transcript and visual evidence stay aligned.

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

### Export To GitHub

After you configure your GitHub token, repository owner, and repository name in Settings, you can export selected extracted issues as GitHub Issues.

### Export To Jira

After you configure your Jira Cloud URL, email, API token, project key, and issue type in Settings, you can export selected extracted issues as Jira issues.

## Session Library

The session library is the main place to revisit earlier work.

You can:

- browse `Today`, `Yesterday`, `Last 7 Days`, `Last 30 Days`, or `All Sessions`
- use a custom date range
- search transcript text, titles, and summaries
- sort by newest first or oldest first
- open a detail pane with transcript, markers, screenshots, summary, and extracted issues
- delete sessions you no longer need

Deleting a session removes it from the library immediately and also removes local screenshot files that BugNarrator manages for that session. Exported files outside the app are not deleted.

## Support Development

BugNarrator is free to use. Donations are optional and separate from any OpenAI costs.

- [Open the PayPal support page](https://www.paypal.com/donate/?hosted_button_id=FWFQ6KCZBWWH8)

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
- restart the app after changing permission settings if needed

### API Key Missing

- open `Settings`
- paste your own OpenAI API key
- click `Validate Key` if you want to check it before recording
- BugNarrator stores the key in macOS Keychain when available

### API Key Rejected Or Revoked

- open `Settings`
- replace the key or remove it and paste a new one
- click `Validate Key`
- try the session again after OpenAI accepts the new key

### Screenshots Not Appearing

- confirm the session was actively recording when the screenshot was requested
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
- markers
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
