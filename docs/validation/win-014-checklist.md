# WIN-014: Real-Desktop Validation of the Windows Parity Rows

Owner ticket: #1133. This checklist is the Windows counterpart of [QA_CHECKLIST.md](../QA_CHECKLIST.md), scoped to the fourteen rows in [parity-matrix.md](../architecture/parity-matrix.md) that are still `In Progress` for Windows.

Those rows used to cite #44 (`RR-002`) as the home of their remaining validation. #44 was closed as completed on 2026-05-13 on the strength of a packaged launch probe — the app stayed alive through initialization with one process running. That is a liveness check, not feature validation, and the ticket's own closing comment deferred the rest to #75, which is also closed. Nothing below is therefore assumed done because #44 is closed.

## How an item is closed

The two classifications close differently, because their evidence differs in kind: a test on `main` is continuous proof that re-runs on every commit, while a screenshot is a snapshot of one build on one machine.

A **`[human]`** item is closed only by an `orc add-evidence` comment on #1133 that names, in this order:

1. the artifact (screenshot, log excerpt, bundle listing, exported body);
2. the commit SHA of `main` the build under test came from;
3. the host id it ran on.

Evidence that could carry a credential (provider status text, export bodies, debug bundles) passes a redaction review before upload; credentials never appear in a comment. Later Windows changes to a row's implementation re-open its item — evidence is pinned to a SHA and is not carried forward silently.

An **`[automation]`** item is closed by naming, in this file, a test that exists on `main` and runs in `dotnet test` under the `windows-build-and-test` CI job. No comment is needed: CI is the evidence. One honest limit: that job is path-gated in `.github/workflows/ci.yml` to `windows/**` and `ci.yml`, so it re-proves the item on every commit *that touches Windows code* — not on every commit. A change to `contract-fixtures/` alone runs neither platform's suite today; that gap is #1140, and until it lands, a fixture-only change is not proof that the named tests still pass. If the named test is later deleted or skipped, the item reopens. Four items below are closed this way on the commit this file landed in.

A matrix row moves to `Shipped` only in a PR that cites the closing evidence for every item under it — the comment for each `[human]` item and the test name for each `[automation]` item.

## Classification

- **`[human]`** — needs a person at a real Windows desktop, real hardware, or a real credential. Automation cannot close it. These stay open on #1133 under `ai/blocked` until a person captures the evidence.
- **`[automation]`** — can be proven by a test, a scripted run, or an emulated environment. If the checklist shows the proof is missing, a separate small implementation ticket is filed; it is not done here.

Most rows carry both kinds. A row moves to `Shipped` only when every item under it is closed.

## The fourteen rows

### 1. Durable workflow: `record -> review -> refine -> export`

- `[human]` One end-to-end session on a real desktop: start recording from the tray, capture at least two screenshots, add one marker, stop, open the session in the review workspace, edit at least one extracted issue (title and severity), export the session bundle. Evidence: the bundle folder listing matching the layout in row 8, and the `windows-shell.log` lines from `recording started` through `recording stopped and review session saved`.
- `[automation]` **Closed.** Each transition is pinned in `BugNarrator.Windows.Tests`: start by `AudioInputDeviceSelectionTests.StartRecordingAsync_WithMixedAudioAndConsent_StartsMixedCaptureWithMicrophone`, stop → save by `RecordingLifecycleServiceMilestone5Tests.StopRecordingAsync_WithConfiguredApiKey_TranscribesAndPersistsCompletedSession`, refine by `ReviewSessionActionServiceTests.ExtractIssuesAsync_WithConfiguredApiKey_SavesUpdatedSession`, export by `BundleExporterTests.FileSessionBundleExporter_ExportsTranscriptAndScreenshots`. No single test runs the whole chain; the human item above is what proves it end to end.

### 2. Compact launch surface (tray shell)

- `[human]` After launch, the tray icon is visible (or reachable through the overflow chevron) and its context menu shows `Start Recording`, `Recording Controls`, `Session Library`, `Settings`, `Quit`. Evidence: one screenshot of the open menu, and one with the icon in the overflow flyout if Windows placed it there.
- `[human]` `Quit` from the tray exits cleanly: no `BugNarrator.Windows` process remains and the log ends with `app exit`. Evidence: the log tail and a process-list line.

### 3. Recording Controls surface

- `[human]` `Recording Controls` opens the window; it shows the idle state, transitions to recording on `Start`, shows elapsed time advancing, and returns to idle on `Stop`. Evidence: three screenshots (idle, recording, idle again) on the same SHA.
- `[human]` Closing the window while recording does not stop the recording; reopening it shows the live state. Evidence: screenshot after reopen plus the log showing no `recording stopped` between close and reopen.

### 4. Single active recording session

- `[human]` Launch the packaged app a second time while it is running: the second process exits 0, one `BugNarrator.Windows` process remains, and the log shows `focus request received from secondary instance`. #44's packaged probe observed exactly this, but its comment names neither a SHA nor a host, so it does not meet the closure rule above and is prior art, not evidence. Evidence: the process-list line and the log excerpt, re-captured.
- `[automation]` No test in `windows/tests` exercises the single-instance path (the only "duplicate" test is a hotkey-conflict check). Verified missing; tracked as #1136 (WIN-017).
- `[human]` While recording, choosing `Start Recording` again from the tray is refused or is a no-op — the log shows no second `recording started`, and the session saved at stop contains one audio track. Evidence: the log excerpt and the bundle listing.

### 5. Screenshot evidence during recording

This is the least-validated row and the most hardware-dependent.

Windows captures a *dragged region*, not a whole monitor: `ScreenshotSelectionOverlayWindow` spans `SystemParameters.VirtualScreen*` (every monitor at once) and prompts "Drag to capture a region", and the PNG is sized from that region. The items test that design, not a whole-screen one.

- `[human]` On a machine with two monitors where the secondary runs at a non-100 % scale (125 % or 150 %), drag a region entirely on the secondary monitor during recording. The saved PNG's pixel dimensions equal the dragged region in *physical* pixels — the logical size the overlay showed multiplied by the scale factor — and the content is what was under the region, not a blurred or offset capture. Evidence: the PNG's dimensions (Explorer properties or `magick identify`), the overlay's reported region size if it shows one, the display settings screenshot showing the scale factor, and the capture itself.
- `[human]` The same on the primary monitor at 100 %: PNG dimensions equal the dragged region exactly. Evidence: as above.
- `[human]` The overlay covers every monitor at once, and a region dragged *across* the boundary between two monitors of different scale captures both halves correctly aligned. Evidence: the capture and a screenshot of the overlay spanning both displays.
- `[automation]` The overlay and capture plumbing under emulated DPI. Verified missing; tracked as #1134 (WIN-015). Do not close this item on the human evidence alone.

### 6. Session Library archive

- `[human]` The library lists every session under `%LOCALAPPDATA%\BugNarrator\Sessions`, newest first, with title, date, and duration matching each `session.json`. Opening one lands in the review workspace. Evidence: a screenshot beside a directory listing with the same count.
- `[human]` Deleting a session removes it from the list and from disk. Evidence: before/after directory listing.

### 7. Review Workspace tabs

- `[human]` The four tabs the product spec names (`docs/architecture/product-spec.md`, "Session Library And Review Workspace") are present and switch without error: `Transcript`, `Screenshots`, `Extracted Issues`, `Summary`. Export is an action on the workspace, not a tab. Evidence: one screenshot per tab on the same session.
- `[human]` An edit made on the `Extracted Issues` tab survives closing and reopening the session. Evidence: `session.json` diff showing the edited field.

### 8. Session Bundle export

- `[automation]` **Closed.** `transcript.md` is byte-compared against `contract-fixtures/transcript.golden.md` on both platforms (#1003). `summary.md` is pinned on its shared subset by `contract-fixtures/summary.golden.md` (#1020); the structure differences outside that subset are deliberate and listed in the matrix's "Current Deliberate Differences" section, so they are not a validation gap. Evidence: `TranscriptMarkdown_MatchesTheCommittedGolden` and `SummaryMarkdownSharedSubset_MatchesTheCommittedGolden` in `BugNarrator.Core.Tests`.
- `[automation]` **Open — defect.** The bundle *layout* is a shared contract too: `contract-fixtures/session-bundle-layout.json` says `manifest.json`, `screenshots/`, and `transcript.md` are always present and `summary.md` only when extraction has run. macOS writes all of that and `TranscriptExporterTests.swift` binds the fixture. Windows writes no `manifest.json` and no Windows test reads the fixture. Tracked as #1137 (WIN-018).
- `[human]` An exported bundle on disk matches the shared layout: `manifest.json`, `transcript.md`, a `screenshots/` directory holding the session's captures, `summary.md` only when extraction has run, and — Windows-only, allowed by the row's parity decision — `annotated-exports/` when annotated images were rendered. `session.json` and `session.wav` are internal session storage and must *not* be in the bundle. Evidence: the directory listing, captured after #1137 lands. Anything outside that list is a stray file.

### 9. Debug Bundle support export

- `[human]` With a provider key configured — any value works; the app does not need to reach a provider for this — export a debug bundle. It contains `system-info.json`, `app-version.txt`, `windows-version.txt`, `recent-log.txt`, `session-metadata.json`, and the configured key appears nowhere in any of them — search the bundle for the key's first eight characters. Evidence: the file listing and the (empty) search result. This item is itself the proof that redaction works; do not upload the bundle.
- `[automation]` **Closed.** `FileDebugBundleExporter_WritesExpectedFilesWithoutSecrets` in `BundleExporterTests` exports a bundle with a configured credential and asserts it appears in none of the written files. The redactor is covered through the exporter, not by a test of its own; that is accepted here because the exporter is the only caller that reaches disk.

### 10. Missing or invalid AI provider recovery

- `[human]` With a completed session on disk, remove the provider key and attempt extraction. The app reports the missing provider and the session is unchanged on disk. Evidence: the status text screenshot and an unchanged `session.json` hash. (The transcription side of this path is already pinned by `RecordingLifecycleServiceMilestone5Tests.StopRecordingAsync_WithoutApiKey_SavesSessionAsNotConfigured`; the extraction side is not, which is why this item and #1135 exist.)
- `[automation]` The same for an invalid key (HTTP 401), a forbidden key (403), and a server error (HTTP 500), served by a fake endpoint. Verified missing; tracked as #1135 (WIN-016). Evidence: the test names once #1135 lands.

### 11. Configurable AI provider setup

- `[human]` Each of the three provider modes reaches a real endpoint: OpenAI with a real key, one OpenAI-compatible hosted endpoint, one local-compatible endpoint. `Validate` reports success for each, and one transcription completes through each. Evidence: the masked status text per mode and the resulting `transcript.md` line count. Never the key.
- `[human]` A wrong key produces a clear failure, not a hang. Evidence: the status text and the log line.

### 12. Recording audio source selection

- `[human]` Record three short sessions on real hardware — microphone only, WASAPI loopback only while audio is playing, and mixed — and play back each `session.wav`. Microphone-only contains the narration and not the playback; loopback-only contains the playback and not the narration; mixed contains both at intelligible levels. Evidence: the three WAV durations and a one-line listening note per file. Do not upload the audio.
- `[human]` Selecting loopback when no output device is active fails with guidance, not a silent empty file. Evidence: the status text.

### 13. Experimental GitHub and Jira export

- `[human]` With a real GitHub token, export one issue that carries severity, component, reproduction steps, and a screenshot annotation. The created issue's body has the same sections in the same order as the macOS export. Evidence: the issue URL on a scratch repo.
- `[human]` The same against a real Jira project. Evidence: the issue key on a scratch project.
- `[automation]` **Closed.** Body rendering is pinned in `IssueExportProviderTests` (`BugNarrator.Windows.Tests`) by `GitHubBuildRequest_IncludesSeverityComponentAndDeduplicationHint`, `JiraBuildRequest_IncludesSeverityComponentAndDeduplicationHint`, `GitHubBuildRequest_RendersReproductionStepsLikeMac`, `JiraBuildRequest_RendersReproductionStepsInTheMacTextShape`, `GitHubBuildRequest_RendersAnnotatedScreenshotsLikeMac`, and `GitHubBuildRequest_CapsReproductionStepsAtTheTrackerBudget`.

### 14. Keyboard-first accessibility

The matrix row's parity decision is "native implementation allowed": the contract is keyboard and assistive-technology support, not identical widgets. macOS validated its baseline in RR-005 with Accessibility API snapshots of Settings, Recording Controls, and Session Library plus a keyboard-only traversal. Windows has no equivalent yet — no automation names appear in the XAML and nothing in `windows/tests` exercises keyboard or screen-reader behaviour.

- `[human]` Keyboard-only traversal of Settings, Recording Controls, and Session Library on a real desktop with the mouse unplugged: every control is reachable with Tab/Shift+Tab in a sensible order, every action is operable with Enter/Space, dialogs close with Esc, and focus is visible at each step. Evidence: a short screen recording or a numbered list of the focus order per window with a screenshot of the focus ring on at least one control per window.
- `[human]` Narrator reads each control in the same three windows with a meaningful name and role — not "button" with no label. Evidence: the spoken names transcribed per window, or an Accessibility Insights for Windows snapshot of each.
- `[automation]` No Windows test covers keyboard reachability or automation names. Whether one is worth adding (Accessibility Insights / UIA automation is heavy) is a decision for after the human items show what is broken; do not file speculatively.

## Blocked on a human

Every `[human]` item above. The specific inputs a person must bring:

| Need | Rows |
| --- | --- |
| A real Windows desktop with the app built from a named SHA | all |
| Narrator (built in) and, ideally, Accessibility Insights for Windows | 14 |
| Two monitors, one at 125 % or 150 % scale | 5 |
| A microphone and an active audio output | 12 |
| A real OpenAI key, one compatible hosted endpoint, one local endpoint | 11 |
| A previously recorded session on disk, with no provider configured | 10 |
| A GitHub token and a scratch repository | 13 |
| A Jira token and a scratch project | 13 |

Until those exist, #1133 stays open under `ai/blocked` with this table as the stated missing input. Automation is not permitted to close it.

## Automation gaps, verified and filed

Checked on the commit this file landed in, by searching `windows/tests` for the coverage each item names:

- **Row 4** — no test exercises the single-instance path; the only test matching "duplicate" is a hotkey-conflict check. #44's probe is a one-time snapshot without a SHA or host. Filed as #1136 (WIN-017).
- **Row 5** — no test in `windows/tests` mentions DPI, scale factor, or a non-100 % geometry. Capture geometry under emulated DPI is unpinned. Filed as #1134 (WIN-015).
- **Row 8** — Windows writes no `manifest.json` and no Windows test binds `contract-fixtures/session-bundle-layout.json`, which macOS both writes and tests. This one is a defect, not just a coverage gap: the bundle is below the shared floor. Filed as #1137 (WIN-018).
- **Row 10** — `OpenAiIssueExtractionService.BuildFailureMessage` maps 401 and 403 to user-facing text, and `OpenAiIssueExtractionServiceTests` already drives `ExtractAsync` through a fake `HttpMessageHandler`, but the only status it ever returns is `OK`; nothing returns 401, 403, or 500. Filed as #1135 (WIN-016), which extends that harness.
