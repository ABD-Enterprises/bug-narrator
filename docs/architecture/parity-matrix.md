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
| Session Bundle export | Shipped | In Progress | Must remain identical | Implemented by Windows Milestone 6; validation remains in #44 and release hardening remains in #75. |
| Debug Bundle support export | Shipped | In Progress | Must remain aligned | Implemented on Windows with redaction/hardening coverage; real support-bundle validation remains in #44. |
| Missing or invalid AI provider recovery | Shipped | In Progress | Must remain identical | Windows preserves completed sessions on missing or failed transcription, but provider terminology/configuration parity is tracked in #73. |
| Configurable AI provider setup | Shipped | Planned in `WIN-007` | Must remain aligned | macOS supports OpenAI plus OpenAI-compatible enterprise/local endpoints; Windows follow-up is tracked in #73. |
| Recording audio source selection | Shipped | Planned in `WIN-008` | Platform-native capture allowed | macOS supports microphone, system audio, and mic plus system audio; Windows follow-up is tracked in #74. |
| Experimental GitHub and Jira export | Shipped as experimental | In Progress | Experimental on both platforms | Windows implementation exists; real credential validation remains in #44. |
| Keyboard-first accessibility | Shipped baseline, validated in RR-005 | In Progress | Native implementation allowed | The contract is clear keyboard and assistive-tech support, not identical widgets. |
| Public release packaging | Shipped as signed, notarized DMG | Planned in `WIN-009` | Platform-native packaging allowed | Windows zip packaging exists; signed tester release work is tracked in #75. |

## Current Deliberate Differences

- macOS is the only production platform today.
- Windows implements the core `record -> review -> refine -> export` path, including session library, review workspace, extraction, export, hotkeys, and hardening coverage, but it still needs real Windows runtime validation in `RR-002` / #44.
- macOS currently has newer configurable AI provider and audio-source surfaces; Windows follow-up parity is tracked in #73 and #74.
- Windows public tester distribution is still blocked on signing/release packaging decisions tracked in #75.

## Update Rules

- Add or update a row whenever a platform-specific deviation becomes intentional.
- Do not use this document to justify undocumented drift.
- If a row changes meaningfully, update the relevant GitHub issue and the relevant implementation roadmap in the same phase. Update [docs/roadmap/roadmap.md](../roadmap/roadmap.md) only when the completed-phase or historical context changes.
