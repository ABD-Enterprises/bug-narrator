# Cross-Platform Parity Matrix

This matrix tracks BugNarrator product contracts across the native macOS app and the in-progress native Windows app.

Use [product-spec.md](product-spec.md) as the source of truth for the contracts named here. Use this matrix to document deliberate platform differences instead of letting them drift into undocumented behavior.

## Status Vocabulary

- `Shipped`: production behavior exists today
- `Implemented On Current Branch`: behavior exists on the active branch, but broader parity or release proof is still incomplete
- `In Progress`: active implementation work exists, but parity is not yet proven
- `Planned`: the contract is accepted, but implementation has not started yet

## Matrix

| Contract / Spec Item | macOS | Windows | Parity Decision | Notes / Rationale |
| --- | --- | --- | --- | --- |
| Durable workflow: `record -> review -> refine -> export` | Shipped | Implemented On Current Branch | Must remain identical | The core Windows workflow exists today; the remaining work is around recovery polish, support surfaces, validation depth, and release parity. |
| Compact launch surface | Shipped as a menu bar window | Implemented On Current Branch as a tray shell | Native surfaces allowed | Windows now exposes a real `Help And Support` surface plus docs, changelog, reporting, release, and support links; remaining work is runtime proof on more Windows setups. |
| Recording Controls surface | Shipped | Implemented On Current Branch | Must remain functionally aligned | Windows now has start, stop, screenshot, session-library, close, and recovery guidance behavior aligned to the current product contract. |
| Single active recording session | Shipped | Implemented On Current Branch | Must remain identical | Duplicate starts and overlapping sessions are disallowed on both platforms. |
| Screenshot evidence during recording | Shipped | Implemented On Current Branch | Native capture implementation allowed | macOS uses ScreenCaptureKit-backed capture; Windows uses a native overlay plus selected-region capture. |
| Session Library archive | Shipped | Implemented On Current Branch | Must remain identical | Windows now has date filters, search, sorting, deletion, retry-needed surfacing, and retry-transcription actions on the current branch. |
| Review Workspace tabs | Shipped | Implemented On Current Branch | Must remain identical | Windows now has the canonical tabs plus retry guidance, generated review summary display, and debug-bundle access; remaining gaps are mostly runtime/provider proof. |
| Generated review summary | Shipped | Implemented On Current Branch | Must remain aligned | Windows now persists and displays generated review summary content, but provider-backed proof on a credentialed Windows machine remains part of `WIN-010`. |
| Session Bundle export | Shipped | Implemented On Current Branch | Must remain identical | Exported bundle stays `transcript.md` plus `screenshots/`. |
| Debug Bundle support export | Shipped | Implemented On Current Branch | Must remain aligned | Diagnostics export exists on Windows, but support-surface discoverability is still a parity gap. |
| Missing or invalid OpenAI key recovery | Shipped | Implemented On Current Branch | Must remain identical | Windows now preserves retry-needed sessions, shows retry guidance in the review surfaces, and allows retrying transcription after settings are fixed. |
| Experimental GitHub and Jira export | Shipped as experimental | Implemented On Current Branch | Experimental on both platforms | Windows export flows exist and the GitHub path now has live Windows proof; Jira export and OpenAI-backed extraction still remain part of `WIN-010`. |
| Support and information surfaces | Shipped | Implemented On Current Branch | Native implementation allowed | Windows now ships a non-placeholder `Help And Support` surface with docs, changelog, repository, issue-reporting, update, support, and debug-bundle actions. |
| Keyboard-first accessibility | Shipped baseline, still under ongoing validation | Implemented On Current Branch | Native implementation allowed | Windows now has the baseline accessibility hardening, labels, status announcements, and keyboard/default-button work, while live assistive-tech and broader runtime proof still need more validation. |
| Permission guidance and recovery affordances | Shipped | Implemented On Current Branch | Native implementation allowed | Windows now surfaces recovery guidance and settings links for microphone and screenshot failures where the platform can help directly. |
| Public release packaging | Shipped as signed, notarized DMG | In Progress in `WIN-011` | Platform-native packaging allowed | Windows now has a public-release scaffold with an Inno Setup installer template and blocker-aware release script, but signed installer and clean-machine public release proof are still missing. |

## Current Deliberate Differences

- macOS is the only production platform today.
- Windows now has the full core workflow plus recovery or retry parity, generated review summary, support surfaces, and baseline accessibility and permission guidance implemented on the active branch.
- The April 4, 2026 RR-002 pass closed the basic tray, recording, screenshot, hotkey, no-key recovery, and debug-bundle runtime proof on Windows, but alternate keyboard layouts, mixed-display proof, live provider credentials, deletion or corrupted-state validation, and signed public release behavior still require later parity cycles.

## Planned Windows Parity Cycle Order

1. `WIN-010 Windows Runtime Proof And Provider Validation`
2. `WIN-011 Windows Public Release Parity`

## Update Rules

- Add or update a row whenever a platform-specific deviation becomes intentional.
- Do not use this document to justify undocumented drift.
- If a row changes meaningfully, update [docs/roadmap/state.json](../roadmap/state.json) and the relevant implementation roadmap in the same phase.
