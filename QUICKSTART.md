# BugNarrator Quickstart

## Install From The DMG

1. Download the latest macOS DMG from [GitHub Releases](https://github.com/deffenda/bugnarrator/releases/latest).
2. Open the DMG.
3. Drag `BugNarrator.app` into `Applications`.
4. Launch BugNarrator from `Applications`.
5. If macOS warns about the app, use the normal Finder `Open` flow for apps you trust.
6. If you launch BugNarrator again while it is already open, the existing menu bar instance should be reactivated instead of creating a second copy.

## First Run

1. Open the menu bar item.
2. Open `Settings`.
3. Paste your own `OpenAI API Key`.
4. Optionally click `Validate Key`.
5. Start a session with `Start Feedback Session`.
6. Keep the recording controls window open while you review, or use the global hotkeys, to insert markers and capture screenshots.
7. Stop the session and review the session library.

## Important Notes

- BugNarrator does not include a built-in OpenAI API key.
- OpenAI transcription and issue extraction use your own OpenAI account and may cost money.
- The app asks for microphone permission only when you start recording. If you deny it, BugNarrator gives you an `Open Microphone Settings` recovery button.
- Screenshot capture may ask for Screen Recording permission on first use. If you deny it, recording can still continue without screenshots.
- If OpenAI rejects your key, BugNarrator sends you back to `Settings` so you can replace it.
- If you hit a bug, use `Copy Debug Info` or `Export Debug Bundle` from the menu bar or Settings before filing an issue.
- BugNarrator intentionally runs as a single-instance app to prevent duplicate menu bar items and competing session state.
- To build or package the app from source, see [docs/Distribution.md](docs/Distribution.md).
