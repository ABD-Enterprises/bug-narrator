# Cross-Platform Parity Matrix

This matrix tracks BugNarrator product contracts across the native macOS app and the in-progress native Windows app.

Use [product-spec.md](product-spec.md) as the source of truth for the contracts named here. Use this matrix to document deliberate platform differences instead of letting them drift into undocumented behavior.

## Status Vocabulary

- `Shipped`: production behavior exists today
- `In Progress`: active implementation work exists, but parity is not yet proven
- `Planned`: the contract is accepted, but implementation has not started yet

## Matrix

| Contract / Spec Item | macOS | Windows | Parity Decision | Notes / Rationale |
| --- | --- | --- | --- | --- |
| Durable workflow: `record -> review -> refine -> export` | Shipped | In Progress | Must remain identical | Windows implements the core workflow, but real desktop validation remains open in `RR-002` / #44. |
| Compact launch surface | Shipped as a menu bar window | In Progress as a tray shell | Native surfaces allowed | Menu bar and tray are platform-native equivalents; Windows still needs real tray validation in #44. |
| Recording Controls surface | Shipped | In Progress | Must remain functionally aligned | Windows has the surface implemented; real recording-controls validation remains in #44. |
| Single active recording session | Shipped | In Progress | Must remain identical | Automated coverage exists on Windows, but real runtime validation remains in #44. |
| Screenshot evidence during recording | Shipped | In Progress | Native capture implementation allowed | Windows has overlay/capture plumbing, but DPI, multi-monitor, and real desktop capture validation remain in #44. |
| Session Library archive | Shipped | In Progress | Must remain identical | Implemented by Windows Milestone 5; #50 is closed as completed, with remaining validation tracked in #44. |
| Review Workspace tabs | Shipped | In Progress | Must remain identical | Implemented by Windows Milestones 5 and 6; #51 is closed as completed, with remaining validation tracked in #44. |
| Session Bundle export | Shipped | In Progress | `transcript.md` must remain identical; bundle contents may differ | Windows `transcript.md` was realigned to the macOS `markdownContent` contract in `WIN-011` / #995 (same section names, ordering, date/duration formats, fallback text, LF endings). Both bundles also contain a `summary.md` when issue extraction has run (macOS since #924; Windows aligned to that same emit condition in #1006). Their contents are not byte-identical yet — see the note below. Validation remains in #44. |
| Debug Bundle support export | Shipped | In Progress | Must remain aligned | Implemented on Windows with redaction/hardening coverage; real support-bundle validation remains in #44. |
| Missing or invalid AI provider recovery | Shipped | In Progress | Must remain identical | Windows preserves completed sessions on missing, incompatible, or failed AI provider setup; real-provider validation remains in #44. |
| Configurable AI provider setup | Shipped | In Progress | Must remain aligned | Windows supports OpenAI, OpenAI-compatible hosted endpoints, and local-compatible endpoints; real-provider validation remains in #44. |
| Recording audio source selection | Shipped | In Progress | Platform-native capture allowed | Windows supports microphone, WASAPI loopback system audio, and mixed microphone + system audio muxed to one track (`WIN-010` / #453). Real-desktop mixed-capture validation remains in #44. |
| Experimental GitHub and Jira export | Shipped as experimental | In Progress | Experimental on both platforms | Windows implementation exists; real credential validation remains in #44. |
| Keyboard-first accessibility | Shipped baseline, validated in RR-005 | In Progress | Native implementation allowed | The contract is clear keyboard and assistive-tech support, not identical widgets. |
| Public release packaging | Shipped as signed, notarized DMG | Repo-side signed tester zip path ready; certificate provisioning required | Platform-native packaging allowed | Windows first tester format is a zip containing signed `BugNarrator.Windows.exe` plus signature and package validation evidence. Installer/MSIX can follow if tester distribution requires it. |

## Current Deliberate Differences

- macOS is the only production platform today.
- Windows implements the core `record -> review -> refine -> export` path, including session library, review workspace, extraction, export, hotkeys, and hardening coverage, but it still needs real Windows runtime validation in `RR-002` / #44.
- macOS currently has mixed microphone plus system audio capture beyond Windows; Windows surfaces the limitation explicitly while system-audio loopback support is available.
- Both platforms export a `summary.md`, and both now write it **only when issue extraction has run** (macOS `TranscriptExporter.swift`, added 2026-08-02 in #924; Windows aligned to that emit condition in #1006). An earlier note here claimed macOS defined `summaryMarkdownContent` but never exported it — that was already untrue when written and has been corrected. The two documents are **not** byte-identical yet: macOS groups issues into one section per category, while Windows renders the richer per-issue detail it collects (reproduction steps, note, export selection). Converging them requires a macOS renderer change, so `summary.md` is not yet pinned in `contract-fixtures/`. Tracked in #1006.
- Windows still has no transcript-section data source, so the macOS `## Transcript Sections` block and screenshot-to-marker linkage remain unimplemented rather than faked. Tracked in #996.
- `transcript.md` parity is now machine-checked rather than asserted twice: both platforms byte-compare against `contract-fixtures/transcript.golden.md` (#1003 wired up the Windows side of #1000/#1001). Doing so exposed and fixed two real Windows divergences — marker notes were not rendered at all (`SessionTimelineMoment` had no note field), and Windows appended a trailing newline macOS does not emit.
- Extracted issues now carry `severity`, `component`, and a `deduplicationHint` on Windows (`WIN-013` / #998), using the same FNV-1a hash contract as macOS so the same issue yields the same hint on both platforms. They are editable in the Windows issue editor (severity and component; the deduplication hint is shown read-only because it is a generated identity) and included in GitHub and Jira export bodies in the same order macOS uses. `reproductionSteps` are now parsed, persisted, and rendered on Windows in `summary.md` and both tracker exports, using the macOS section shapes and the same `reproductionStepLimit`/`listEntryLimit` caps and truncation markers; they are display-only in the Windows editor (macOS allows editing). `screenshotAnnotations` are now parsed, clamped with the same normalized-coordinate rules as macOS, persisted, and rendered in both tracker exports using the macOS no-rendered-asset line shape. Windows does not draw annotated PNG files — macOS does that with CoreGraphics/ImageIO, and the macOS export already has a fallback line for the un-rendered case, which is what Windows emits. The remaining slices on #998 are the annotated-image renderer and making reproduction steps editable in the Windows issue editor.
- Windows public tester distribution is blocked on external code-signing certificate provisioning, not missing repo scripts. The release entrypoint and manual GitHub Actions workflow are in place for the signed tester zip path.

## Update Rules

- Add or update a row whenever a platform-specific deviation becomes intentional.
- Do not use this document to justify undocumented drift.
- If a row changes meaningfully, update the relevant GitHub issue and the relevant implementation roadmap in the same phase. Update [docs/roadmap/roadmap.md](../roadmap/roadmap.md) only when the completed-phase or historical context changes.
