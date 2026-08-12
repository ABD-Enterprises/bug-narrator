# Changelog

## Unreleased

- [NEW] The local Parakeet transcription server is now a signed, notarized download published with each release (`bugnarrator-transcription-macos-arm64.zip`). Every in-app instruction previously named `local-transcription/venv/...` — a path only a source checkout has — so the free, no-upload transcription option was unreachable for anyone who installed from the DMG. Settings > AI Engines now links straight to it (#959).

- [CHANGE] You can now record before configuring an AI provider. Recording was blocked until a provider was set up, walling the entire first run behind a paid API key — even though the record-now/transcribe-later path already existed and preserves the session for retry. The start button now says the session will be saved and kept ready to transcribe (#959).
- [NEW] The menu bar offers the bundled sample session while your library is empty. The sample shipped with a button in the session library's empty state, but a new install opens the menu bar, not that window — so the one surface a first-time user sees had no route to it (#959).

- [DOCS] At-rest encryption is now described exactly as shipped. Session bodies and the search index are encrypted; screenshots, recorded audio, and the operational log are not. SECURITY.md carries a per-file table, and the previous broader wording ("your sessions are encrypted on disk") is corrected in the README and User Guide. The asymmetry is a deliberate decision — screenshots have to stay openable by Finder and Preview, audio has to stay re-readable for retry — and FileVault is named as the control that covers the rest (#954).

- [DOCS] Backups and machine migration are now documented. Session bodies are encrypted with a this-device-only Keychain key, so a Time Machine restore, a Migration Assistant move, or a dead Mac leaves the library unreadable — the files return, the key does not. README, SECURITY.md, and the User Guide now say so and point at Export Data as the key-independent escape hatch to run *before* migrating (#955).

- [INTERNAL] Release builds destined for GitHub Releases now fail closed. `PUBLIC_RELEASE=YES` refuses a dirty tree, an untagged HEAD, unsigned builds, skipped notarization, and the fail-open notarization flag — then re-verifies the finished artifact instead of trusting that the steps ran. The DMG container is now signed; previously only the app inside it was, and `codesign -dv` on the shipped 1.0.41 image reported "not signed at all" (#963).
- [INTERNAL] Every DMG build writes a `.provenance.txt` recording the commit, tag, tree state, signing authority, and notarization status, so a download can be tied back to what produced it (#963).

- [INTERNAL] `BugNarratorUITests` now gates merges. It was wired into CI as advisory in #922 and failed 2 of 7 on every run since, so it read as coverage while proving nothing. The two assertions that could not pass on a hosted runner were removed — deleted with the reason recorded, not weakened — and the leg is blocking (#949).

- [NEW] "Check for Updates" now tells you whether a newer version exists instead of just opening the releases page. It reads the public releases feed, compares it to your build, and opens the new release if there is one — or says you are current and opens nothing. A failed check says so and still opens the releases page. The request is unauthenticated and carries no identifiers (#961).

- [CHANGE] The system-audio consent notice now names the obligation rather than just the fact: it reads "I am responsible for getting everyone's consent before recording system audio", and the explanation says outright that many places require every participant's agreement and that BugNarrator cannot obtain it for you (#951).
- [DOCS] The User Guide has a Recording Consent section, and the product spec documents system-audio capture in its evidence-capture, privacy, and experimental-features contracts — the capability shipped without appearing in any of them (#951).

- [FIX] Issue extraction now works against local models. Every request carried `image_url` screenshot parts and forced `response_format: json_object`, both of which standard Ollama / LM Studio models reject with a 400 — so extraction failed outright for the Local-Compatible provider the README recommends. Requests are now shaped to the provider's actual capabilities (#956).
- [FIX] Extraction no longer gives up after 10 seconds. The application cap discarded slow-but-valid answers even though the transport allowed 120s. Hosted providers now get 60s and local providers 120s (#956).

- [INTERNAL] A PR that breaks the build can no longer merge. Branch protection required only two ubuntu jobs that never compile Swift, so the 797-test macOS suite ran and gated nothing. A `required-checks` job now aggregates every CI job and is the required context (#962).
- [INTERNAL] The blocking CI gate is hermetic. It ran the board-state audit, which queries the live GitHub board, so a board hiccup or one mislabeled issue could fail every open PR. That audit now runs as its own advisory job; local `validate.sh` still runs it by default (#962).

- [CHANGE] **Screenshots are no longer uploaded to your AI provider by default.** Issue extraction embedded up to four screenshot images in every request, while the README listed screenshots under "Data that stays local on your Mac". Uploading is now opt-in via Settings > Diagnostics & Privacy > "Send screenshots to the AI provider"; filenames and timestamps still travel so the model can tie narration to a capture (#950).
- [FIX] README, SECURITY.md, and the User Guide now list exactly what leaves the machine per feature, including screenshot images and the tracker issue text used for duplicate review — the latter was disclosed nowhere (#950).
- [FIX] Issue titles and summaries fetched from GitHub or Jira are now delimited and labeled untrusted in the duplicate-review prompt. Anyone able to file an issue in a configured tracker could otherwise place instructions into a prompt sent to your AI provider (#950).

- [FIX] Reaching the 500-session retention limit no longer strands data. The evicted session's screenshots and preserved audio used to stay on disk with nothing referencing them — invisible, unreachable, and never cleaned up. They are now removed with the session, and BugNarrator says how many sessions the limit dropped instead of doing it silently. The limit is now documented (#960).
- [FIX] A failed artifacts deletion is no longer logged as a success. The error was swallowed and the "removed" line was written regardless, so the logs claimed screenshots were deleted while they were still on disk (#960).

- [INTERNAL] The docs site now deploys from CI (`.github/workflows/docs-site.yml`) on pushes to `main` that touch `site/` or `docs/`. It was published by hand and had not been republished since 2026-05-11, so the live pages served pre-transfer repository links for three months while the repo was correct. The build refuses to publish when a generated doc mirror is stale (#964).

- [FIX] Library search now searches the **whole** transcript. It only ever indexed the first 160 characters, so anything said after the opening sentence was unfindable — in the feature the product is built around (#957).
- [CHANGE] The session index (`sessions.index.json`) is now encrypted at rest like session bodies are. It previously held transcript text in the clear beside encrypted session files; making search full-text without this would have widened that from a 160-character preview to entire transcripts. Indexes written by older builds still load and are re-written protected on the next save (#957, part of #954).

- [FIX] QUICKSTART no longer tells you to click past a Gatekeeper warning. Releases are signed, notarized, and stapled, so that warning means the download is not the release — verify the checksum instead. This is the guidance #909 corrected in the README; QUICKSTART had been left behind (#964).
- [FIX] The docs-site publish runbook pointed at the pre-transfer `deffenda.github.io` URL and hardcoded a maintainer username (#964).
- [INTERNAL] `site/docs/user/user-manual.md` is now generated from the canonical `docs/user/user-manual.md` by `scripts/sync_site_docs.py`, and `validate.sh` fails when it drifts. It previously claimed to mirror the canonical manual while being a separately written document that had diverged (#964).

- [FIX] A remote `http://` AI endpoint is now rejected instead of warned about. Previously the warning was advisory and nothing consumed it as a gate, so one mistyped scheme could send your API key and your recordings across the network unencrypted. Loopback, private-range, `.local`, and single-label hosts are unaffected — the local LM Studio / Ollama / Parakeet paths and the shipped `http://localhost` defaults all still work (#953).

- [CHANGE] **Transcripts are no longer copied to the clipboard automatically.** "Auto-copy transcript to clipboard" (Settings > General) now defaults to off — it put the full transcript on the system pasteboard after every save, where clipboard managers retain it, and that was never disclosed. If you deliberately turned it on, your choice is preserved; if you never touched it and want the old behavior, turn it on (#952).
- [FIX] The README no longer claims BugNarrator "does not include automatic telemetry" while writing `operational-telemetry.jsonl`. Nothing is transmitted — that part was true — but the local log, what it records, where it lives, and how to turn it off are now stated plainly (#952).

- [FIX] An OpenAI account with no credits left now says so, instead of reporting a rate limit and retrying three times. New OpenAI accounts start with no credits, so this was the likeliest outcome of a fresh key's first transcription. Genuine rate limits still back off and retry, and the recording is still preserved for retry either way (#958).

- [NEW] First-run welcome tour. A new install is walked through choosing an AI provider, granting microphone access, and assigning the three capture hotkeys, instead of landing in a blank menu bar. It is skippable at every step, reopenable from Help > Show Welcome Tour, and never appears for someone who already has recorded sessions. Nothing is bound or configured without an explicit press (#357).
- [FIX] Settings now also opens on the AI Engines pane when a provider has a credential but fails its compatibility check, rather than landing on General — which cannot resolve it (#357, extending #911).
- [FIX] What's New now appears after an update for users whose session history is stored in the partitioned format. The check read a cache that loads lazily and is empty at launch, so an established library looked like a brand-new install and the release notes were skipped (#357).

## 1.0.41 - 2026-08-05

- [FIX] Settings now opens on the AI Engines pane when no usable AI provider credential is configured, instead of General — the pane a new user is sent to Settings to fix is the one they land on (#911).
- [FIX] The menu bar and empty session library no longer invite you to start a recording while the record control is disabled. Setup copy now names the prerequisite instead of promising recording works without it (#910).
- [CHANGE] Exported session bundles now include `summary.md` — the review summary and extracted issues — alongside `transcript.md` and `screenshots/`, plus a `manifest.json` describing the bundle's contents (#914).
- [FIX] Exporting a session bundle no longer fails outright when a referenced screenshot file has been moved or deleted. The bundle exports with the screenshots that remain, and the missing files are listed in `manifest.json` (#914).
- [FIX] Install instructions no longer tell you to Control-click past a Gatekeeper warning. Releases are Developer ID signed, notarized, and stapled, so that warning does not appear (#909).

### Internal

- [INTERNAL] Corrected the 1.0.40 release date, restored the missing 1.0.37 entry, and separated internal notes from user-facing ones in this changelog (#915).
- [INTERNAL] CodeQL now analyzes Swift — the `include_swift` dispatch input never reached the language matrix, so Swift was silently unscanned (#919).
- [INTERNAL] `BugNarratorUITests` are now executed by CI; the target existed but no workflow ran it (#922).
- [INTERNAL] Stopped tracking agent scratch logs that had been committed to the repo (#923).
- [INTERNAL] Extracted the seven permission and configuration recovery sections out of `MenuBarView.swift` into `MenuBarView+RecoverySections.swift`, 873 → 724 lines (#433).

## 1.0.40 - 2026-07-23

- [FIX] Clarified the failure paths when starting a system-audio recording — reason-labelled diagnostic logs distinguish the experimental-feature-flag gate, the consent-acknowledgement gate, and macOS TCC audio-capture permission; the TCC failure path now names the exact System Settings pane to open (#856).
- [FIX] Updated the Settings > Recording Audio > Audio Source hint to name both prerequisites (consent toggle + System Settings > Privacy & Security > Screen & System Audio Recording) so users can preempt the "first-time capture" macOS prompt.
- [FIX] Made the recording-controls transcription progress copy provider-aware, so Local (Parakeet) sessions no longer claim audio is being uploaded to OpenAI.
- [FIX] Report zero-frame system-audio recordings as system-audio capture/setup failures with recovery guidance, show the active recording source in the controls window, and avoid making Local (Parakeet) look responsible for an empty system-audio file.

### Internal

- [INTERNAL] Updated the accessibility regression guardrail to follow the extracted transcript and settings view files.
- [INTERNAL] Decomposed `SettingsStore.swift` by 338 lines (1963 → 1625) across seven byte-preserving extension slices — `+Display`, `+DisplayMask`, `+Normalization`, `+Models`, `+Tokens`, `+Placeholders`, `+TranscriptionInput`.
- [INTERNAL] Extracted `ReviewWorkspaceShell` and `IssueExportTargetEditors` (`IssueGitHubTargetEditor` + `IssueJiraTargetEditor`) from `TranscriptView`, shrinking that file by 239 lines (1882 → 1643).
- [INTERNAL] Extracted `RawTranscriptSection` from `TranscriptView` into a dedicated view file.
- [INTERNAL] Added a non-blocking CI probe job that dual-runs `runtime-guardrails` on the `[self-hosted, Linux, ARM64]` org runner alongside `ubuntu-latest`, so a subsequent PR can flip the workflow's portable jobs once the probe reports green.

## 1.0.39 - 2026-06-11

- [FIX] Stopped the menu bar microphone level meter from crashing when CoreAudio delivers level updates on its realtime callback queue.

## 1.0.38 - 2026-06-11

- [FIX] Refreshed menu-bar AI setup state when the saved OpenAI credential changes, so Settings and the menu no longer disagree about a usable key.
- [FIX] Blocked recording starts until AI transcription setup is usable, defaulted fresh installs to English transcription hints, and added transcript quality warnings for wrong-script output.

### Internal

- [INTERNAL] Split AI setup, transcription defaults, and issue extraction settings into an encapsulated SwiftUI section with UI coverage.
- [INTERNAL] Added a repository docs audit to keep maintainer docs aligned with the local-first validation path and CI unit-test scope.
- [INTERNAL] Added a cheap Windows tester release preflight so missing signing secrets fail before reserving a Windows runner.
- [INTERNAL] Moved Swift/project change detection ahead of the self-hosted macOS CI job so config-only PRs no longer reserve macOS runner slots.
- [INTERNAL] Added the EAS auto-merge trusted-author allowlist so eligible green PRs do not repeatedly fail on missing gate configuration.
- [INTERNAL] Added effort-leak guardrails so stale AI issue states, duplicate PR claims, and superseded CI runs are caught before agents spend more time.

## 1.0.37 - 2026-06-01

- [FIX] Refreshed the menu-bar AI setup state when saved OpenAI credential readiness changes, so Settings and the menu no longer disagree about a usable key.

### Internal

- [INTERNAL] Added UI regression coverage proving a saved OpenAI key shows Settings as ready and keeps the Validate and Remove actions enabled.

## 1.0.36 - 2026-05-27

- [FIX] Isolated AI provider credentials so OpenAI-compatible, local-compatible, and Local (Parakeet) setup states no longer reuse or display credentials saved for another provider.
- [FIX] Clarified Local (Parakeet) setup status to show that no API key is required, and automatically disabled automatic issue extraction when switching to or loading the transcription-only Parakeet provider.
- [FIX] Hid local transcription server exception details from HTTP error responses while keeping full diagnostics in the server logs, resolving the open CodeQL stack-trace exposure alert.
- [FIX] Cleared the docs-site `ws` dependency advisory by updating the locked `webpack-dev-server` dependency path.
- [FIX] Replaced a shellcheck-flagged Xcode discovery pattern in CI with `find` while preserving the existing Xcode 26 selection behavior.
- [CHANGE] Removed the launch-time unexpected-quit recording recovery importer and its recovered-recording prompts; leftover crash audio is no longer surfaced as a persistent transcription failure or retry action.
- [FIX] Logged a diagnostics error when the transcription retry attempt count cannot be saved durably, so operators can see when recovery state is in memory only instead of silently disappearing on the next launch.
- [FIX] Respected task cancellation between resolving displays and writing the screenshot file, so cancelling a region screenshot mid-flight no longer drops a PNG on disk after the user dismissed the selection.
- [CHANGE] Repointed the default GitHub export repository and in-app project links from `deffenda/bug-narrator` to `ABD-Enterprises/bug-narrator`. Fresh installs and UI-test seeded settings now resolve to the canonical organization repo; existing installs keep whatever owner/repo the user previously configured.
- [FIX] Cleared in-flight issue-extraction/export progress when an issue mutation (toggle selection, edit) write fails, so the extraction progress spinner no longer keeps running on top of an unrelated error toast.
- [FIX] Restored the auto-open of Settings on credential-failure recording starts and the in-flight progress cleanup on any recording-start failure, so a missing/invalid API key surface still directs the user to Settings and stale issue-extraction/export badges from a prior pipeline no longer linger.
- [FIX] Rendered the "Transcription Pending" timeline entry in the review workspace using the active AI provider's recovery guidance, so Local (Parakeet) sessions no longer surface OpenAI-specific text in the review surface.
- [FIX] Removed the successful side's leftover audio file when only one of the microphone or system-audio recorders fails to stop a mixed recording, so the abandoned file is no longer picked up as a crash-recovery candidate on the next launch.
- [FIX] Removed the zero-byte preserved retry audio file when transcription preservation rejects an empty recording, so the session artifacts directory no longer keeps an unusable audio file behind.
- [FIX] Removed the partial mixed-recording output file when the export or post-export size check fails, so a corrupt artifact is no longer left in the recovered-recordings directory to be imported as a crash recovery on the next launch.

## 1.0.35 - 2026-05-19

- Added local Parakeet transcription server for offline, zero-cost speech-to-text on Apple Silicon via MLX.
- Added Local (Parakeet) AI provider in Settings that auto-configures to localhost:8422 with no API key required.
- Added standalone binary builder so the transcription server runs without a Python installation.
- Fixed Keychain access in debug builds to avoid a stuck modal dialog when the signing identity differs from production.

## 1.0.34 - 2026-05-19

- Split the remaining `AppState` execution paths into dedicated recording, screenshot, transcription recovery, and session-library controllers so the release build is easier to reason about and maintain.
- Centralized `AppState` error normalization and typed event names so diagnostics and UI state transitions stay consistent across recording, recovery, and export flows.
- Added release-signing hardening carried forward from the local packaging pipeline so the shipped DMG remains notarized, stapled, and aligned with the current source version.

## 1.0.33 - 2026-05-06

- Added concurrent retry guard to prevent duplicate transcription retry attempts from compounding failures.
- Added retry attempt counting to preserved sessions so repeated failures surface clearer guidance instead of silently accepting infinite retries.
- Added exponential backoff with Retry-After header support for OpenAI 429 rate-limit responses in the transcription client.
- Fixed DMG packaging to staple the notarization ticket to the app bundle before packaging, so users who drag BugNarrator out of the DMG get an app that passes Gatekeeper even offline. Previously only the DMG carried the stapled ticket, which caused "BugNarrator is damaged" alerts when the online notarization check failed or timed out.

## 1.0.32 - 2026-04-29

- Hardened screenshot region capture so an abandoned selection cannot leave future screenshot attempts stuck in a busy state, and stopping or discarding a recording now cancels any pending screenshot selection cleanly.

## 1.0.31 - 2026-04-28

- Hardened recording startup so duplicate start actions while a draft is already active restore the active recording state instead of failing or discarding in-progress artifacts.
- Scoped the active recording banner in the Session Library to the active draft session only, so unrelated saved sessions no longer show the current recording at the top.
- Moved live recorder output into BugNarrator's recoverable recordings directory and allowed oversized source recordings to transcribe through validated chunks, improving resilience for long sessions.

## 1.0.30 - 2026-04-27

- Added deterministic local UI regression coverage for Settings, Session Library issue export, and Recording Controls so token fields, export buttons, per-issue tracker targets, and recording controls are exercised without touching production Keychain, microphone, GitHub, Jira, or OpenAI services.
- Hardened UI accessibility targets for the main app dialogs with stable scroll-region labels and protected those labels in the accessibility regression check.
- Routed extracted issues to GitHub and Jira using per-issue repository, project, issue-type, and label targets from the Session Library, with local regression coverage for grouped GitHub and Jira exports.
- Improved Settings setup guidance with explicit OpenAI, GitHub, and Jira readiness status rows and clearer credential prerequisites.

## 1.0.29 - 2026-04-27

- Restored the Open BugNarrator at Startup control when macOS reports the login item is not registered yet, so the signed app can register itself instead of showing the control as unavailable.
- Added isolated Settings UI regression coverage for the startup toggle and GitHub/Jira token fields so field lockups and disabled Settings controls are caught locally before release.

## 1.0.28 - 2026-04-27

- Replaced Settings token inputs with AppKit-backed credential fields that avoid macOS password/autofill UI while keeping saved tokens masked at rest.
- Limited Jira issue-type refreshes to explicit project picker changes so Settings field focus and scrolling cannot trigger repeated metadata reloads.

## 1.0.27 - 2026-04-27

- Switched Jira project discovery to Jira Cloud project search and issue-type discovery to the project issue-type APIs instead of relying on brittle create-metadata project listing responses.
- Hardened Jira metadata decoding so malformed or partial rows are skipped and unexpected metadata formats surface a useful Jira error instead of Swift's generic missing-data decode message.

## 1.0.26 - 2026-04-27

- Fixed tracker setup readiness so Jira project loading is enabled after entering only the Jira URL, email, and API token, before any project or issue type has been loaded.
- Fixed Jira Cloud URL normalization for pasted `https://...atlassian.net` values and added regression coverage for loading Jira projects before a project selection exists.
- Fixed GitHub setup readiness so repository validation can use typed owner/name values without requiring a picker-loaded repository ID, and replaced the misleading token placeholder that looked like a saved token.

## 1.0.25 - 2026-04-27

- Added launch recovery for crash-left recordings so recovered audio and matching transcript files are imported into the session library instead of staying hidden in Application Support.
- Added transcript quality findings for empty, suspiciously short, abruptly cut off, or repeated-loop transcript output so users can review risky transcripts before relying on them.
- Added local audio upload and issue-extraction request budgets to reject oversized audio before upload and cap long transcript/screenshot payloads before OpenAI issue extraction.
- Surfaced session-store backup recovery and recent tracker export receipt history in the session library review surface.
- Hardened release validation with bundle identifier, microphone usage, and audio-input entitlement checks, and moved CodeQL to manual/scheduled runs to avoid automatic Swift analysis on every PR or push.

## 1.0.24 - 2026-04-27

- Blocked app termination while a recording is active so BugNarrator no longer strands in-progress call audio in temporary storage when the app receives Quit.
- Stopped secure settings fields from persisting to Keychain on every edit and moved those saves to explicit user actions so settings changes no longer trigger prompt storms.
- Fixed the Jira API token field so it no longer re-locks itself while you type after the deferred secure-save change.
- Hardened the local release path so DMG packaging bootstraps its own `dmgbuild` environment, pins the host macOS build destination explicitly, and keeps the startup keychain smoke probe opt-in instead of default.

## 1.0.23 - 2026-04-17

- Fixed long-form transcription reliability by chunking extended recordings before upload, then stitching the returned transcript text and segment timestamps back together so BugNarrator no longer truncates or loops repeated sections on longer sessions.

## 1.0.22 - 2026-03-28

- Preserved finished recordings when transcription cannot start because the OpenAI API key is missing, invalid, or revoked, and surfaced retry-needed sessions more clearly in the menu bar and session library so recovery is easier after relaunch.
- Hardened keyboard and VoiceOver behavior across the menu bar, recording controls, session library, extracted issues, and settings, and added a lightweight accessibility regression check for the most accessibility-sensitive app surfaces.
- Added a canonical product spec, a cross-platform parity matrix, synced the docs site to the main onboarding, user, and product pages, and seeded internal release-summary automation to tighten future release execution.
- Expanded the Windows validation baseline so CI now runs on `phase/*` branches, executes both Windows test projects, packages the Windows workspace, validates the packaged zip contents, and launches the packaged Windows app in a headless smoke mode before treating the artifact as healthy.

## 1.0.21 - 2026-03-16

- Trimmed `Export Session Bundle` so it now writes only `transcript.md` and the `screenshots/` folder.
- Refreshed the README, quickstart, user guide, testing notes, QA checklist, and release checklist so they match the current control-window, screenshot-first, and debug-support workflow.
- Hardened the session-library review pane so the right-hand workspace adapts more cleanly to narrow widths instead of collapsing metadata, actions, and review rows into unreadable vertical fragments.

## 1.0.20 - 2026-03-16

- Tightened the review workspace so the tab strip uses less vertical space and no longer leaves a large dead zone above extracted issues content.
- Simplified menu bar and settings surfaces by removing duplicate About/debug actions, hiding unset hotkeys, and promoting the session library as a first-class action.
- Kept debug bundle export out of the normal session export flow and hid the menu bar debug-bundle action behind the Option key.
- Hardened region screenshot capture against intermittent white frames by excluding BugNarrator's own windows from capture and waiting briefly for the selection overlay to leave the compositor.
- Moved Jira export email persistence out of plain preferences storage, migrated legacy saved values into secure storage, and added regression coverage for the secure Jira-email path.

## 1.0.19 - 2026-03-15

- Hardened session and debug bundle export so BugNarrator now writes bundles through an atomic staging directory, adds `recent-log.txt` to exported session bundles, and avoids overwriting duplicate screenshot filenames inside an export.
- Added launch-time permission and session-store diagnostics plus shutdown cleanup for timers, process activity, and hotkey registrations so menu bar lifecycle issues are easier to diagnose and recover.
- Added `./scripts/release_smoke_test.sh` and `./scripts/cleanup_local_build_apps.sh` to tighten pre-release validation and keep local build copies from polluting macOS permissions or Spotlight results after release testing.
- Tightened screenshot artifact validation and DMG packaging checks so BugNarrator now verifies non-empty screenshot files and confirms the microphone entitlement survives the signed app and mounted DMG flow.
- Added a tester narration guide and refreshed QA, release, and distribution docs so external testers have clearer recording and release validation instructions.

## 1.0.18 - 2026-03-15

- Hardened OpenAI issue extraction decoding so BugNarrator now accepts array-based message content, fenced JSON, and a few schema variations instead of failing on valid structured responses with a generic format error.
- Fixed the Screen Recording permission request path for the menu bar app by activating BugNarrator before asking macOS for screenshot access, which improves first-run and post-reset screenshot prompting.
- Tightened the review workspace so the `Extracted Issues` tab only appears when extraction actually returned issues, and empty extractions now fall back to the summary view instead of leaving the user on a dead-end issues screen.
- Marked GitHub and Jira issue export as experimental across the app and docs so the current maturity of those integrations is explicit before setup or use.

## 1.0.17 - 2026-03-15

- Fixed the signed DMG packaging flow so BugNarrator keeps the macOS audio-input entitlement when the release app is re-signed for Developer ID distribution.
- Added the BugNarrator entitlements file to the project so the shipped app retains microphone capability in notarized public builds instead of losing it during packaging.

## 1.0.16 - 2026-03-15

- Fixed the signed app's microphone prompt path again by using macOS media-capture authorization to trigger the system microphone prompt, then resolving the final state from both app-level and capture-device permission APIs.
- Improved microphone permission recovery when one macOS permission API stayed stale or disagreed with the other after resets or repeated local testing.

## 1.0.15 - 2026-03-15

- Fixed another microphone permission recovery bug where BugNarrator could stay stuck in a blocked state after a TCC reset or stale app-level permission read instead of refreshing and retrying the macOS prompt path.
- Added regression coverage for blocked microphone states that refresh into a grant during recording preflight.
- Clarified the public repo policy so BugNarrator is not currently accepting outside code contributions or pull requests.

## 1.0.14 - 2026-03-15

- Fixed a microphone permission state bug where BugNarrator could mix the older capture-device authorization API with the modern app-level microphone permission API and incorrectly conclude that access was denied before macOS had shown the prompt.
- Switched microphone prompting and preflight state on macOS 14+ to the modern app-level permission API so first-run and post-reset permission requests behave more reliably for the signed app.

## 1.0.13 - 2026-03-15

- Fixed a microphone permission prompt path bug for the menu bar app so BugNarrator now activates itself before requesting microphone access from macOS.
- Improved first-run and post-reset microphone behavior for the signed app when macOS had a mismatched not-determined vs denied permission state and was failing to surface the system prompt.

## 1.0.12 - 2026-03-15

- Fixed a microphone permission regression where BugNarrator could enter a fake recording state and produce silent sessions even though macOS still had microphone access blocked.
- Tightened recording preflight so denied or restricted microphone permission now blocks recording immediately instead of letting a recorder activation probe override the system privacy state.
- Added regression coverage to keep blocked microphone states from starting a session or silently recording nothing.

## 1.0.11 - 2026-03-15

- Simplified the recording controls window by removing the standalone marker button and making screenshot capture the primary way to mark important moments during a session.
- Tightened the right-hand review workspace so the header, actions, tabs, and content use less vertical space and start reading immediately.
- Removed the separate `Markers` tab from the review workspace while keeping older marker-only sessions readable in the transcript timeline.
- Unified screenshot and marker timeline entries so screenshot captures create one cleaner combined review event instead of duplicate marker and screenshot rows.
- Removed built-in hotkey defaults so recording and screenshot shortcuts now start unassigned until the user explicitly chooses them.
- Removed shortcut suggestions and the `Default` hotkey button, and changed duplicate-assignment behavior so conflicts are rejected with a clear message instead of silently overriding another action.
- Removed the obsolete standalone marker hotkey runtime and settings path, and now clear any legacy stored marker shortcut during settings load.
- Polished the drag-to-select screenshot overlay with clearer visual feedback, a lightweight hint, and a cleaner cancellation path.
- Refined the `Screenshots` tab so captured images show cleaner thumbnails, timestamps, linked markers, and direct-open behavior.
- Replaced full-display screenshot capture with a drag-to-select region overlay so BugNarrator saves only the area the tester chooses.
- Kept screenshot captures attached to the active session with the same timestamp and automatic marker behavior, while treating `Esc` and zero-size selections as clean cancellations.
- Added screenshot capture regression coverage for region cropping, off-display selections, and cancelled selections.
- Refreshed the release and QA docs to match the compact screenshot-driven workflow, and revalidated the current workspace with passing debug tests, a clean Release build, and a successful local DMG package build.

## 1.0.10 - 2026-03-15

- Centralized microphone and screenshot permission preflight so recording and screenshot actions validate permissions and real capture capability before starting.
- Fixed a false-denied microphone path where recording preflight could pass but the recorder immediately re-ran permission checks and blocked the same session start anyway.
- Added screenshot-specific preflight so denied Screen Recording access no longer leaks into the main recording flow.
- Added targeted automated coverage for microphone preflight, screenshot preflight, stale permission recovery, and capture-setup failures.

## 1.0.9 - 2026-03-15

- Added a dedicated microphone permission service with structured recording preflight, clearer denied vs restricted vs unavailable states, and better local-testing guidance for unsigned Xcode builds.
- Fixed review-workspace tab selection so switching between sessions with different content does not leave the right-hand pane on an invalid or stale tab.
- Switched screenshot previews in the review workspace to cached thumbnails instead of repeatedly decoding full-size images, which reduces lag and memory waste in screenshot-heavy sessions.
- Fixed a single-instance regression that could terminate the XCTest app host when another BugNarrator copy was already running during local validation.
- Added targeted automated coverage for review-workspace state rules, session-bundle export contents, and the XCTest single-instance bypass path.

## 1.0.8 - 2026-03-15

- Simplified the menu bar so recording actions now live only in the BugNarrator controls window, with the menu focusing that window instead of duplicating start or stop actions.
- Reduced the controls window size, preserved its position between launches, and stopped it from jumping across the screen when starting a session or capturing screenshots.
- Added clearer microphone recovery guidance for local unsigned builds so testing from DerivedData explains why macOS may ask for permission again for different app bundle paths.

## 1.0.7 - 2026-03-15

- Replaced the floating recording HUD with a persistent recording controls window and configurable start, stop, marker, and screenshot shortcuts.
- Added structured local diagnostics, debug bundle export, and copyable debug info for safer GitHub issue reporting without exposing credentials.
- Added single-instance enforcement plus session-library and detail-view performance improvements for larger local histories.
- Polished the menu bar, settings, session review workspace, and product copy to make BugNarrator feel more focused and easier to use daily.
- Upgraded the DMG packaging flow so the mounted disk uses the BugNarrator icon and opens to a cleaner drag-to-Applications Finder window.
- Removed the duplicate microphone recovery prompt from the menu bar while keeping the direct microphone settings recovery action.

## 1.0.6 - 2026-03-14

- Added a compact floating recording HUD so marker and screenshot controls stay available without reopening the menu bar window.
- Changed screenshot capture to auto-insert a marker so screenshots stay anchored to the session timeline.
- Updated the start-session flow so recording can begin without an OpenAI API key, while still requiring the key before transcription.

## 1.0.5 - 2026-03-14

- Rebuilt and republished BugNarrator from the current stabilized main branch as a fresh signed, notarized, and stapled macOS release.

## 1.0.4 - 2026-03-14

- Fixed microphone permission detection on macOS 14+ so BugNarrator reads the app's actual granted microphone state and no longer stays blocked after access has been enabled in System Settings.

## 1.0.3 - 2026-03-14

- Fixed a microphone-permission recovery bug where BugNarrator could keep showing a stale “microphone denied” error even after access had been granted in System Settings.

## 1.0.2 - 2026-03-14

- Migrated screenshot capture from the deprecated CoreGraphics screenshot path to ScreenCaptureKit on macOS 14+, while preserving session associations, marker proximity, and screenshot-specific permission recovery.
- Added direct recovery guidance and an `Open Microphone Settings` action when microphone permission is denied.
- Updated the menu bar status card to wrap longer error text and expand for recovery messaging instead of truncating it.
- Hardened post-transcription persistence so a completed transcript stays open as an unsaved session if local history storage fails after transcription.
- Updated the session library to prefer the latest in-memory session snapshot when persistence falls behind, preventing stale issue edits and summaries from disappearing out of the detail view.
- Prevented GitHub and Jira exports from running against deleted or stale sessions and added date-bucket regression coverage around midnight in local timezones.
- Hardened the DMG packaging script to verify branded icon resources, DMG contents, and public-release validation steps before publishing.
- Added regression coverage for deferred interactive secret loading and the menu bar status presentation rules behind the permission and error fixes.

## 1.0.1 - 2026-03-14

- Fixed the app icon pipeline so BugNarrator ships with branded app icon assets instead of a generic fallback.
- Simplified Support Development to a single PayPal action and aligned the app UI, documentation, and tests with that flow.
- Fixed the initial install experience by avoiding an unexpected credential prompt on first launch before the user explicitly uses a key-dependent feature.

## 1.0.0 - 2026-03-14

- Renamed the app to BugNarrator and aligned the product identity across the project.
- Added a scalable session library with date filters, search, sorting, and session deletion.
- Added markers, screenshot capture, extracted issues, and GitHub or Jira export workflows.
- Added a polished About BugNarrator window, project links, support-development action, and in-app changelog viewer.
- Added a repeatable DMG packaging workflow, release documentation, and clearer download or support guidance for end users.

## 0.9.0 - 2026-03-13

- Added transcript capture, local session history, and clipboard copy after transcription.
- Added OpenAI API key management with Keychain storage and validation.
- Added issue extraction and structured export foundations for developer tooling.

## 0.8.0 - 2026-03-12

- Added the initial macOS menu bar recording workflow for narrated software testing sessions.
- Added background microphone capture, Whisper transcription, and a transcript review window.
