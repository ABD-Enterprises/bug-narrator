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
| Durable workflow: `record -> review -> refine -> export` | Shipped | In Progress | Must remain identical | The UI can differ by platform, but the workflow contract stays stable. |
| Compact launch surface | Shipped as a menu bar window | In Progress as a tray shell | Native surfaces allowed | Menu bar and tray are platform-native equivalents. |
| Recording Controls surface | Shipped | In Progress | Must remain functionally aligned | Start, stop, screenshot, and close actions should exist on both platforms. |
| Single active recording session | Shipped | In Progress | Must remain identical | Duplicate starts and overlapping sessions are disallowed everywhere. |
| Screenshot evidence during recording | Shipped | In Progress | Native capture implementation allowed | macOS uses ScreenCaptureKit-backed capture; Windows can use a native overlay plus selected-region capture. |
| Session Library archive | Shipped | Planned in `WIN-005` | Must remain identical | Date filters, search, sorting, and deletion remain part of the durable archive contract. |
| Review Workspace tabs | Shipped | Planned in `WIN-005` / `WIN-006` | Must remain identical | Canonical tabs remain `Transcript`, `Screenshots`, `Extracted Issues`, and `Summary`. |
| Session Bundle export | Shipped | Planned in `WIN-006` | Must remain identical | Exported bundle stays `transcript.md` plus `screenshots/`. |
| Debug Bundle support export | Shipped | Planned in `WIN-006` | Must remain aligned | Diagnostics may differ, but secrets must stay excluded on both platforms. |
| Missing or invalid OpenAI key recovery | Shipped | Planned in `WIN-005` | Must remain identical | Finished recordings must stay recoverable and retryable instead of being lost. |
| Experimental GitHub and Jira export | Shipped as experimental | Planned in `WIN-006` | Experimental on both platforms | Integration maturity stays explicit until it is hardened and validated. |
| Keyboard-first accessibility | Shipped baseline, still under ongoing validation | Planned | Native implementation allowed | The contract is clear keyboard and assistive-tech support, not identical widgets. |
| Public release packaging | Shipped as signed, notarized DMG | Planned | Platform-native packaging allowed | macOS uses DMG/notarization; Windows will use signed installer packaging. |

## Current Deliberate Differences

- macOS is the only production platform today.
- Windows milestone work through tray shell, recording lifecycle, and screenshot scaffolding is present in the repo but still blocked on real Windows runtime validation in `RR-002`.
- macOS currently has the stronger recovery story because preserved-session retry has already shipped there.

## Update Rules

- Add or update a row whenever a platform-specific deviation becomes intentional.
- Do not use this document to justify undocumented drift.
- If a row changes meaningfully, update [docs/roadmap/roadmap.md](../roadmap/roadmap.md) and the relevant implementation roadmap in the same phase.
