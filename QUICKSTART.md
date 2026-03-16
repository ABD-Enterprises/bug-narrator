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
5. Click `Show Recording Controls`.
6. Start a session with `Start Recording`.
7. Keep the recording controls window open while you review, or assign your own optional global hotkeys in Settings if you want keyboard control for stopping and screenshot capture.
8. Stop the session and review the session library.
9. If you are recording a real test pass, follow the [Tester Narration Guide](docs/UserGuide.md#tester-narration-guide) so the transcript, summary, and extracted issues stay clear.

## Important Notes

- BugNarrator does not include a built-in OpenAI API key.
- Global hotkeys start disabled until you assign them yourself.
- OpenAI transcription and issue extraction use your own OpenAI account and may cost money.
- The app runs a microphone preflight before recording starts. If access is denied, restricted, or audio capture cannot actually be prepared, BugNarrator blocks recording early and explains what to fix.
- If you deny microphone access, BugNarrator gives you an `Open Microphone Settings` recovery button.
- If you are testing unsigned local builds from Xcode, keep launching the same app copy when possible. macOS can treat different build paths as different apps for microphone approval.
- Screenshot capture may ask for Screen Recording permission on first use. If you deny it, recording can still continue without screenshots.
- If OpenAI rejects your key, BugNarrator sends you back to `Settings` so you can replace it.
- If support asks for diagnostics, hold `Option` while the menu bar window is open to reveal `Export Debug Bundle`.
- For manual testing sessions, use the [Tester Narration Guide](docs/UserGuide.md#tester-narration-guide) so BugNarrator captures better repro steps and summaries.
- GitHub and Jira issue export are available, but both integrations are currently experimental.
- BugNarrator intentionally runs as a single-instance app to prevent duplicate menu bar items and competing session state.
- To build or package the app from source, see [docs/Distribution.md](docs/Distribution.md).
