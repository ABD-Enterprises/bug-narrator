# User Manual

BugNarrator is organized around one durable workflow:

`record -> review -> refine -> export`

This site page mirrors the canonical user manual in the repository and stays focused on end-user behavior.

## Before You Start

You need:

- a macOS 14 or later Mac
- your own OpenAI API key for transcription and issue extraction
- microphone permission for recording
- Screen Recording permission if you want screenshots

## Recording Workflow

1. Open the menu bar item.
2. Open `Settings` and add your OpenAI API key.
3. Click `Show Recording Controls`.
4. Click `Start Recording`.
5. Narrate what you are doing and capture screenshots when important evidence appears.
6. Click `Stop Recording`.

If the OpenAI key is missing, invalid, or revoked when recording stops, BugNarrator preserves the finished session so you can restore the key and retry transcription later.

## Review Workflow

After transcription finishes, BugNarrator opens the session library so you can review:

- `Transcript`
- `Screenshots`
- `Extracted Issues`
- `Summary`

Sessions waiting for transcription retry are surfaced in both the menu bar window and the session library until you retry them successfully.

## Export Options

- `Export Session Bundle`
  creates `transcript.md` plus a `screenshots/` folder
- `Export to GitHub (Experimental)`
- `Export to Jira (Experimental)`

## Accessibility

BugNarrator supports keyboard-first use across the menu bar window, recording controls, session library, and settings.

- recording controls expose default and cancel actions
- session-library filters and review tabs announce selected state
- settings and hotkey controls use explicit accessibility labels

## More Detail

- [Canonical user manual in the repo](https://github.com/deffenda/bugnarrator/blob/main/docs/user/user-manual.md)
- [Detailed user guide](https://github.com/deffenda/bugnarrator/blob/main/docs/UserGuide.md)
- [Tester Narration Guide](https://github.com/deffenda/bugnarrator/blob/main/docs/UserGuide.md#tester-narration-guide)
