# User Manual

This is the canonical structured user manual for BugNarrator.

Detailed companion guide:

- [docs/UserGuide.md](../UserGuide.md)

## What BugNarrator Is

BugNarrator is a macOS menu bar app for narrated software testing sessions. It helps you:

- record a spoken review session
- capture screenshots as evidence during the session
- transcribe the session
- review transcript, screenshots, summary, and extracted issues
- export a session bundle or selected issues

## Before You Start

You need:

- a macOS 14 or later Mac
- your own OpenAI API key for transcription and issue extraction
- microphone permission for recording
- Screen Recording permission if you want screenshots

## Install

1. Download the latest DMG from GitHub Releases.
2. Open the DMG.
3. Drag `BugNarrator.app` into `Applications`.
4. Launch the installed app from `Applications`.

## First-Run Setup

1. Open the menu bar item.
2. Open `Settings`.
3. Paste your OpenAI API key.
4. Optionally validate the key.

BugNarrator does not ship with a built-in OpenAI key.

## Recording Workflow

1. Click `Show Recording Controls`.
2. Click `Start Recording`.
3. Speak while you continue using the app you are reviewing.
4. Use `Capture Screenshot` when something important or broken appears.
5. Click `Stop Recording`.

The recording controls window stays open until you close it.

If the OpenAI key is missing, invalid, or revoked when the recording finishes, BugNarrator preserves the finished session in the library so you can restore the key and retry transcription later.

Sessions waiting for transcription retry are also surfaced in the menu bar window and at the top of the session-library list, so the recovery flow stays visible after relaunch.

## Review Workflow

After transcription finishes, BugNarrator opens the session library so you can review:

- Transcript
- Screenshots
- Extracted Issues
- Summary

## Export Options

Current export options:

- `Export Session Bundle`
  creates `transcript.md` plus a `screenshots/` folder
- `Export to GitHub (Experimental)`
- `Export to Jira (Experimental)`

## Accessibility

BugNarrator supports keyboard-first use across the menu bar window, recording controls, session library, and settings.

- the recording controls window exposes a default action for the main enabled recording button and uses `Esc` to close
- custom session-library filters, tabs, and export controls announce labels and selected state for VoiceOver
- settings fields and hotkey controls use explicit labels instead of relying only on placeholder text

Accessibility validation is still an active maintenance area. If a screen reader or keyboard-only flow feels unclear, export a debug bundle and report the issue so the exact surface can be audited.

## Troubleshooting

Common fixes:

- microphone blocked: use `Open Microphone Settings`
- screenshot blocked: use `Open Screen Recording Settings`
- invalid OpenAI key: open `Settings`, replace the key, and retry

For support, hold `Option` while the menu bar window is open to reveal `Export Debug Bundle`.

## Related Docs

- [Detailed User Guide](../UserGuide.md)
- [Tester Narration Guide](../UserGuide.md#tester-narration-guide)
- [Onboarding Guide](../onboarding/getting-started.md)
