# WIN-014: Real-Desktop Validation of the Windows Parity Rows

Owner ticket: #1133. This checklist is the Windows counterpart of [QA_CHECKLIST.md](../QA_CHECKLIST.md), scoped to the fourteen rows in [parity-matrix.md](../architecture/parity-matrix.md) that are still `In Progress` for Windows.

Those rows used to cite #44 (`RR-002`) as the home of their remaining validation. #44 was closed as completed on 2026-05-13 on the strength of a packaged launch probe — the app stayed alive through initialization with one process running. That is a liveness check, not feature validation, and the ticket's own closing comment deferred the rest to #75, which is also closed. Nothing below is therefore assumed done because #44 is closed.

## Where status lives

This file is a procedure, not a status board. It says what each item requires and what automated coverage exists in the codebase as of the commit it landed in; it does not say whether an item is done. **The status of every item lives on #1133**, per the repository rule that task state stays on the external board and never in repository Markdown. When this file and a comment on #1133 disagree, the comment is current and this file is stale.

## What counts as evidence

The two classifications are proven differently, because their evidence differs in kind: a test on `main` is continuous proof that re-runs on every commit touching Windows code, while a screenshot is a snapshot of one build on one machine.

A **`[human]`** item is satisfied only by an `orc add-evidence` comment on #1133 that names, in this order:

1. the artifact (screenshot, log excerpt, bundle listing, exported body);
2. the commit SHA of `main` the build under test came from;
3. the host id it ran on.

Evidence that could carry a credential (provider status text, export bodies, debug bundles) passes a redaction review before upload; credentials never appear in a comment. Evidence is pinned to a SHA and is not carried forward silently: a later Windows change to a row's implementation means that row needs fresh evidence, recorded on #1133.

An **`[automation]`** item is satisfied by a test that exists on `main` and runs in `dotnet test` under the `windows-build-and-test` CI job. Where such a test exists today, this file names it as a fact about the codebase. One honest limit: that job is path-gated in `.github/workflows/ci.yml` to `windows/**` and `ci.yml`, so it re-proves the item on every commit *that touches Windows code* — not on every commit. A change to `contract-fixtures/` alone runs neither platform's suite today; that gap is #1140, and until it lands, a fixture-only change is not proof that the named tests still pass. If a named test is later deleted or skipped, the item needs a replacement, recorded on #1133.

A matrix row moves to `Shipped` only in a PR that cites the evidence for every item under it — the comment for each `[human]` item and the test name for each `[automation]` item.

## Classification

- **`[human]`** — needs a person at a real Windows desktop, real hardware, or a real credential. Automation cannot satisfy it. Their status is tracked on #1133.
- **`[automation]`** — can be proven by a test, a scripted run, or an emulated environment. If the checklist shows the proof is missing, a separate small implementation ticket is filed; it is not done here.

Most rows carry both kinds. A row moves to `Shipped` only when every item under it has evidence on #1133.

## The fourteen rows

### 1. Durable workflow: `record -> review -> refine -> export`

- `[human]` One end-to-end session on a real desktop: start recording from the tray, capture at least two screenshots (each capture is what creates a timeline marker on Windows — `ScreenshotCapturePlanner` is the only producer of `SessionTimelineMoment`; there is no standalone marker action), stop, open the session in the review workspace, edit at least one extracted issue (title and severity), export the session bundle. Evidence: the bundle folder listing matching the layout in row 8, and the `windows-shell.log` lines from `recording started` through `recording stopped and review session saved`.
- `[automation]` Covered today. Each transition is pinned in `BugNarrator.Windows.Tests`: start by `AudioInputDeviceSelectionTests.StartRecordingAsync_WithMixedAudioAndConsent_StartsMixedCaptureWithMicrophone`, stop → save by `RecordingLifecycleServiceMilestone5Tests.StopRecordingAsync_WithConfiguredApiKey_TranscribesAndPersistsCompletedSession`, refine by `ReviewSessionActionServiceTests.ExtractIssuesAsync_WithConfiguredApiKey_SavesUpdatedSession`, export by `BundleExporterTests.FileSessionBundleExporter_ExportsTranscriptAndScreenshots`. No single test runs the whole chain; the human item above is what proves it end to end.

### 2. Compact launch surface (tray shell)

- `[human]` After launch, the tray icon is visible (or reachable through the overflow chevron) and its context menu shows the entries `TrayShell.BuildMenu` creates, which are also the canonical terms in `product-spec.md`: a `Status: …` line, `Start Recording`, `Stop Recording`, `Capture Screenshot`, `Show Recording Controls`, `Open Session Library`, `Settings`, `About`, `Quit`. Evidence: one screenshot of the open menu, and one with the icon in the overflow flyout if Windows placed it there.
- `[automation]` Partly covered today. `TrayPresentationStateTests.SupportEntries_MatchTheMacProductInfoMenuInOrder` and `Links_EqualTheMacConstants` (#1143) pin the View Documentation, Report an Issue, View Changelog, and Support Development entries and their macOS destinations. Still missing against the spec: the recovery-guidance entry and Check for Updates — both need surfaces Windows does not have yet (a structured blocker model; an update checker) and are not filed until someone decides their shape.
- `[human]` `Quit` from the tray exits cleanly: no `BugNarrator.Windows` process remains and the log ends with `app exit`. Evidence: the log tail and a process-list line.

### 3. Recording Controls surface

- `[human]` `Show Recording Controls` opens the window; it shows the idle state, transitions to recording on `Start`, and returns to idle on `Stop`. Evidence: three screenshots (idle, recording, idle again) on the same SHA.
- `[automation]` Not covered today, and the behaviour itself is missing: `RecordingControlsWindow` has no elapsed-time display or timer (macOS `RecordingControlPanelView` has one), so "elapsed time advancing" cannot pass on any current build. Tracked as #1142 (WIN-021); once it lands, the human item above gains "shows elapsed time advancing" with the #1142 test as its automation half.
- `[human]` Closing the window while recording does not stop the recording; reopening it shows the live state. Evidence: screenshot after reopen plus the log showing no `recording stopped` between close and reopen.

### 4. Single active recording session

- `[human]` Launch the packaged app a second time while it is running: the second process exits 0, one `BugNarrator.Windows` process remains, and the log shows `focus request received from secondary instance`. #44's packaged probe observed exactly this, but its comment names neither a SHA nor a host, so it does not meet the evidence rule above and is prior art, not evidence. Evidence: the process-list line and the log excerpt, re-captured.
- `[automation]` Covered today. `SingleInstanceTests.SecondInstance_IsRefusedAndSignalsTheFirstToFocus` and `PrimaryInstance_IsReleasedOnDispose_SoTheNextLaunchCanOwnIt` pin the process half with two instances on separate threads (the mutex is re-entrant per thread, so same-thread would prove nothing); `AudioInputDeviceSelectionTests.StartRecordingAsync_WhileAlreadyRecording_IsRefusedWithoutStartingASecondCapture` pins the second-Start half (#1136).
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
- `[human]` Every date filter the spec names is offered — `Today`, `Yesterday`, `Last 7 Days`, `Last 30 Days`, `Retry Needed`, `All Sessions`, `Custom Date Range` — and `Retry Needed` shows only sessions whose transcription failed. Evidence: a screenshot of the filter list and one of `Retry Needed` applied to a library containing one failed session.
- `[human]` Search narrows the list by a word that appears only in one session (title or transcript), and the sort control flips between newest-first and oldest-first with the order visibly reversing. Evidence: two screenshots of the search result and two of each sort order.
- `[automation]` Not covered today, and the behaviour itself is missing: `SessionLibraryDateRange` has no `Retry Needed` value. Tracked as #1144 (WIN-023).

### 7. Review Workspace tabs

- `[human]` The four tabs the product spec names (`docs/architecture/product-spec.md`, "Session Library And Review Workspace") are present and switch without error: `Transcript`, `Screenshots`, `Extracted Issues`, `Summary`. Export is an action on the workspace, not a tab. Evidence: one screenshot per tab on the same session.
- `[human]` An edit made on the `Extracted Issues` tab survives closing and reopening the session. Evidence: `session.json` diff showing the edited field.
- `[human]` Run extraction on a session whose transcript yields no issues (a few words of small talk): the workspace lands on `Summary`, not an empty `Extracted Issues` list, as product-spec.md requires. Evidence: a screenshot after extraction.
- `[automation]` Not covered today, and the behaviour itself is missing: `SessionLibraryWindow.ExtractIssuesAsync` never changes the selected tab. Tracked as #1145 (WIN-024).

### 8. Session Bundle export

- `[automation]` Covered today. `transcript.md` is byte-compared against `contract-fixtures/transcript.golden.md` on both platforms (#1003). `summary.md` is pinned on its shared subset by `contract-fixtures/summary.golden.md` (#1020); the structure differences outside that subset are deliberate and listed in the matrix's "Current Deliberate Differences" section, so they are not a validation gap. Evidence: `TranscriptMarkdown_MatchesTheCommittedGolden` and `SummaryMarkdownSharedSubset_MatchesTheCommittedGolden` in `BugNarrator.Core.Tests`.
- `[automation]` Not covered today, and the behaviour itself is missing. The bundle *layout* is a shared contract too: `contract-fixtures/session-bundle-layout.json` says `manifest.json`, `screenshots/`, and `transcript.md` are always present and `summary.md` only when extraction has run. macOS writes all of that and `TranscriptExporterTests.swift` binds the fixture. Windows writes no `manifest.json` and no Windows test reads the fixture. Tracked as #1137 (WIN-018).
- `[human]` An exported bundle on disk matches the shared layout: `manifest.json`, `transcript.md`, a `screenshots/` directory holding the session's captures, `summary.md` only when extraction has run, and — Windows-only, allowed by the row's parity decision — `annotated-exports/` when annotated images were rendered. `session.json` and `session.wav` are internal session storage and must *not* be in the bundle. Evidence: the directory listing, captured after #1137 lands. Anything outside that list is a stray file.

### 9. Debug Bundle support export

- `[human]` With a provider key configured — any value works; the app does not need to reach a provider for this — export a debug bundle. It contains `system-info.json`, `app-version.txt`, `windows-version.txt`, `recent-log.txt`, `session-metadata.json`. Configure distinct AI-provider, GitHub, and Jira credentials first (any values); none of the three appears in any file — search the whole bundle for the first eight characters of each. Evidence: the file listing and the (empty) search result. This item is itself the proof that redaction works; do not upload the bundle.
- `[automation]` Covered today. `FileDebugBundleExporter_WritesExpectedFilesWithoutSecrets` in `BundleExporterTests` exports a bundle with a configured credential and asserts it appears in none of the written files. The redactor is covered through the exporter, not by a test of its own; that is accepted here because the exporter is the only caller that reaches disk. `FileDebugBundleExporter_LeaksNoneOfTheThreeCredentialTypesIntoAnyFile` (#1148) carries AI, GitHub, and Jira canaries — bare and as a Basic pair — and scans every file the bundle wrote; it caught a bare Atlassian token leaking before the redactor learned that shape.

### 10. Missing or invalid AI provider recovery

- `[human]` With a completed session on disk, remove the provider key and attempt extraction. The app reports the missing provider and the session is unchanged on disk. Evidence: the status text screenshot and an unchanged `session.json` hash. (The transcription side of this path is already pinned by `RecordingLifecycleServiceMilestone5Tests.StopRecordingAsync_WithoutApiKey_SavesSessionAsNotConfigured`; the extraction side is not, which is why this item and #1135 exist.)
- `[human]` Stop a recording with no provider configured, then restore the key and retry transcription from the library; the session gains a transcript. The spec requires this later retry. Evidence: the `Retry Needed` filter before, the retry action, and the transcript after.
- `[automation]` Not covered today, and the behaviour itself is missing: Windows has no retry-transcription action; the only transcription call is at stop time. Tracked as #1146 (WIN-025).
- `[automation]` Covered today. `OpenAiIssueExtractionServiceTests.ExtractAsync_WhenTheProviderRejectsTheRequest_ThrowsTheMappedMessage` (401, 403, 500) and `ExtractAsync_WhenTheProviderReturnsAnErrorEnvelope_PrefersItsMessage` pin the user-facing text and the exception type that keeps the session unsaved (#1135). The session-on-disk guarantee itself is structural in `ReviewSessionActionService`, which saves only after `ExtractAsync` returns.

### 11. Configurable AI provider setup

- `[human]` Each of the three provider modes reaches a real endpoint: OpenAI with a real key, one OpenAI-compatible hosted endpoint, one local-compatible endpoint. `Validate` reports success for each, one transcription completes through each, **and one issue extraction completes through each** — transcription (`OpenAiTranscriptionClient`, `audio/transcriptions`) and extraction (`OpenAiIssueExtractionService`, `chat/completions`) are separate consumers, and an endpoint can serve one and not the other. Evidence: the masked status text per mode, the resulting `transcript.md` line count, and the extracted issue count per mode. Never the key.
- `[human]` A wrong key produces a clear failure, not a hang. Evidence: the status text and the log line.

### 12. Recording audio source selection

- `[human]` Record three short sessions on real hardware — microphone only, WASAPI loopback only while audio is playing, and mixed — and play back each `session.wav`. Microphone-only contains the narration and not the playback; loopback-only contains the playback and not the narration; mixed contains both at intelligible levels. Evidence: the three WAV durations and a one-line listening note per file. Do not upload the audio.
- `[human]` Selecting loopback when no output device is active fails with guidance, not a silent empty file. Evidence: the status text.
- `[human]` System-audio and mixed capture start only when all three of the spec gate hold — experimental flag on, system-audio source selected, consent ticked — and are refused with a consent-style error when any one is missing. Evidence: the refusal text for each missing condition.
- `[automation]` Not covered today, and the behaviour itself is missing: `WindowsAppSettings` has the source and the consent but no experimental flag, so Windows gates on two of three. Tracked as #1147 (WIN-026).

### 13. Experimental GitHub and Jira export

- `[human]` With a real GitHub token, export one issue that carries severity, component, reproduction steps, and a screenshot annotation. The created issue's body has the same sections in the same order as the macOS export. Evidence: the issue URL on a scratch repo.
- `[human]` The same against a real Jira project. Evidence: the issue key on a scratch project.
- `[automation]` Covered today. Body rendering is pinned in `IssueExportProviderTests` (`BugNarrator.Windows.Tests`) by `GitHubBuildRequest_IncludesSeverityComponentAndDeduplicationHint`, `JiraBuildRequest_IncludesSeverityComponentAndDeduplicationHint`, `GitHubBuildRequest_RendersReproductionStepsLikeMac`, `JiraBuildRequest_RendersReproductionStepsInTheMacTextShape`, `GitHubBuildRequest_RendersAnnotatedScreenshotsLikeMac`, and `GitHubBuildRequest_CapsReproductionStepsAtTheTrackerBudget`.

### 14. Keyboard-first accessibility

The matrix row's parity decision is "native implementation allowed": the contract is keyboard and assistive-technology support, not identical widgets. macOS validated its baseline in RR-005 with Accessibility API snapshots of Settings, Recording Controls, and Session Library plus a keyboard-only traversal. Windows has no equivalent yet — no automation names appear in the XAML and nothing in `windows/tests` exercises keyboard or screen-reader behaviour.

The product spec's Accessibility Contract names five surfaces: the compact launch surface, recording controls, session library, review workspace, and settings. On Windows the compact launch surface is the tray icon and its menu.

- `[human]` Keyboard-only use of the tray: with the mouse unplugged, reach the tray icon (Win+B, then arrow keys), open its menu with Enter or the menu key, move through every entry with the arrow keys, and activate `Show Recording Controls`. Evidence: a screenshot of the open menu with keyboard focus on an entry, and the log line for the window it opened.
- `[human]` Keyboard-only traversal of Settings, Recording Controls, Session Library, and the review workspace's four tabs: every control is reachable with Tab/Shift+Tab in a sensible order, every action is operable with Enter/Space, tabs switch with the arrow keys, the selected tab and any selected filter announce as selected, dialogs close with Esc, and focus is visible at each step. Evidence: a short screen recording or a numbered list of the focus order per window with a screenshot of the focus ring on at least one control per window.
- `[human]` Narrator reads each control on those surfaces with a meaningful name and role — not "button" with no label — and announces transient status changes (recording started, recording stopped, export finished). Evidence: the spoken names transcribed per window, or an Accessibility Insights for Windows snapshot of each.
- `[automation]` Not covered today. No `AutomationProperties` appear anywhere in the Windows views, so unlabeled controls have nothing for Narrator to read, and no test would notice a label being added and later lost. Tracked as #1141 (WIN-020): explicit names on non-self-describing controls plus a test that constructs each window on an STA thread and walks its controls — the views are built in C# (`App.xaml` is the only XAML file), so a XAML-parsing test would pass vacuously.

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

This table is the stated missing input; the ticket state that reflects it lives on #1133. Automation is not permitted to satisfy a `[human]` item.

## Automation gaps, verified and filed

Status of each is on its own ticket, not here.

Checked on the commit this file landed in, by searching `windows/tests` for the coverage each item names:

- **Row 2** — the four help entries landed in #1143; recovery guidance and Check for Updates remain unfiled pending a design decision (see the row).
- **Row 3** — `RecordingControlsWindow` shows no elapsed time at all; macOS does. A behaviour gap, not just a coverage gap. Filed as #1142 (WIN-021).
- **Row 4** — was a gap; closed by #1136, see the row.
- **Row 6** — no `Retry Needed` filter. Filed as #1144 (WIN-023).
- **Row 7** — no fallback to `Summary` after an empty extraction. Filed as #1145 (WIN-024).
- **Row 5** — no test in `windows/tests` mentions DPI, scale factor, or a non-100 % geometry. Capture geometry under emulated DPI is unpinned. Filed as #1134 (WIN-015).
- **Row 8** — Windows writes no `manifest.json` and no Windows test binds `contract-fixtures/session-bundle-layout.json`, which macOS both writes and tests. This one is a defect, not just a coverage gap: the bundle is below the shared floor. Filed as #1137 (WIN-018).
- **Row 14** — no `AutomationProperties` anywhere in the Windows views (which are C#; `App.xaml` is the only XAML file); nothing names controls for Narrator and nothing tests it. Filed as #1141 (WIN-020), whose test walks constructed windows because the views are C#, not XAML.
- **Row 9** — was a gap (no Jira canary, two files checked); closed by #1148, which also found and fixed a real bare-token leak.
- **Row 10** — no retry-transcription action exists. Filed as #1146 (WIN-025).
- **Row 12** — no experimental system-audio flag; the gate is two of three. Filed as #1147 (WIN-026).
- **Row 10 (401/403/500)** — was a gap; closed by #1135, see the row.
