# Post-1.0.0 Bug Log

This document tracks the bugs surfaced after `BugNarrator 1.0.0` was cut and what happened to each one.

It is intentionally product-facing rather than code-facing: the goal is to preserve what users actually experienced, the impact, and the release or patch where the issue was addressed.

## Summary

After `1.0.0`, the bugs surfaced fell into four buckets:

- install and first-run trust issues
- branding and icon packaging problems
- support / donation UX inconsistencies
- permission-recovery and error-message usability gaps

## Issues Surfaced Since 1.0.0

| ID | Surfaced behavior | User impact | Status | Fixed in |
| --- | --- | --- | --- | --- |
| `BN-P1-001` | The shipped app sometimes showed a generic app icon instead of the BugNarrator icon. | Made the app feel unfinished and harder to trust after install. | Fixed | `1.0.1` |
| `BN-P1-002` | The DMG / public release artifact could still contain an app bundle with missing icon resources, so Finder showed the generic placeholder icon even when source assets were correct. | Public downloads could look broken even after the source-side icon fix existed. | Fixed | `1.0.1` release artifact refresh |
| `BN-P1-003` | The menu bar label and visual identity still felt generic. | Reduced product polish and made the app feel less distinctive in the menu bar. | Fixed | `1.0.1` |
| `BN-P1-004` | First launch could trigger a credential prompt while the app tried to read or migrate stored OpenAI credentials. | Created immediate trust friction during install and made the app feel unsafe. | Fixed | `1.0.1` |
| `BN-P1-005` | The Support Development flow used three donation amounts even though the product only needed a simple path to the PayPal support page. | Added unnecessary decision friction and UI clutter. | Fixed | `1.0.1` |
| `BN-P1-006` | When microphone permission was denied, BugNarrator only showed an error message and did not help the user recover. | Users could get stuck without a direct path to fix the problem. | Fixed | `1.0.2` |
| `BN-P1-007` | Long error messages could be truncated in the top status card of the menu bar window. | Important recovery guidance was cut off exactly when the user needed it most. | Fixed | `1.0.2` |
| `BN-P1-008` | After enabling microphone access in System Settings, BugNarrator could keep showing the stale denied state until the user manually retried or restarted. | Made the app appear blocked even after the permission issue was already fixed. | Fixed | `1.0.3` |

## Notes Per Issue

### BN-P1-001: Generic app icon in the built app

- Symptom: the installed app showed the standard generic app icon.
- Root cause: the icon asset catalog was not reliably making it into the built app bundle in every distribution path.
- Fix: the asset catalog pipeline was corrected and the generated icon assets were rebuilt.

### BN-P1-002: Generic icon in the DMG / release artifact

- Symptom: even when the source app icon looked correct locally, the downloaded DMG could still install a copy that showed the generic icon.
- Root cause: the release packaging path was using an incomplete app bundle without the expected `Contents/Resources` icon assets.
- Fix: the packaging flow was rebuilt, verified against the actual DMG contents, then reissued as a signed, notarized, stapled `1.0.1` release artifact.

### BN-P1-003: Generic menu bar identity

- Symptom: the menu bar presentation still felt like a stock utility rather than a branded product.
- Root cause: the menu bar label relied on a generic SF Symbol treatment.
- Fix: the menu bar label was replaced with a more BugNarrator-specific visual treatment.

### BN-P1-004: First-run credential prompt

- Symptom: first launch could trigger a Keychain / credential prompt before the user intentionally opened Settings or started a key-dependent action.
- Root cause: startup secret-loading and legacy credential migration were still touching Keychain paths too eagerly.
- Fix: startup reads were made non-interactive, and interactive legacy-key migration was deferred until the user explicitly initiated a relevant action.

### BN-P1-005: Overcomplicated support / donation flow

- Symptom: the app exposed multiple donation amounts even though the hosted PayPal page already handled support.
- Root cause: the support UI modeled donation tiers instead of the actual support path.
- Fix: the app now presents a single `Open PayPal Donation Page` action and aligns docs/tests with that simpler flow.

### BN-P1-006: Microphone-denied flow lacked recovery guidance

- Symptom: users saw a microphone-denied error but were not given a direct fix path.
- Root cause: the app surfaced the error but did not attach a recovery action to the menu bar status area.
- Fix: the menu bar status card now includes explicit guidance plus an `Open Microphone Settings` action with a fallback chain:
  - direct Microphone privacy pane
  - Security / Privacy settings
  - System Settings app

### BN-P1-007: Status card truncated long error messages

- Symptom: long error text could be clipped in the top status card.
- Root cause: the menu bar window used a fixed width with status text that did not explicitly wrap and expand.
- Fix: the status text now wraps, the card grows vertically, and the menu widens for longer error states when needed.

### BN-P1-008: Stale microphone-denied state after access was granted

- Symptom: a user could grant microphone access in System Settings, return to BugNarrator, and still see the app presenting itself as blocked by microphone denial.
- Root cause: the error state reflected the previous permission check and was not reconciled when the app became active again.
- Fix: BugNarrator now re-checks microphone permission when the app becomes active and clears the stale denied state once access is authorized again.

## Current State

As of the current local workspace state:

- `1.0.1` already covers the icon pipeline, support-flow simplification, and first-run credential-prompt fix.
- `1.0.2` covers the microphone-recovery UX, multiline status-card sizing, and the ScreenCaptureKit screenshot modernization.
- the current diagnostics and supportability pass adds structured local diagnostics logging, `Copy Debug Info`, and `Export Debug Bundle` so user-reported issues can carry better support context without exposing credentials.
- the release-hardening pass now keeps successfully transcribed sessions visible as unsaved drafts if local history persistence fails, and it prevents exports from running against stale or deleted session snapshots.
- the DMG packaging script now validates icon resources in both the built app and the mounted DMG, which reduces regression risk for the original icon-shipping bugs.
- screenshot capture now uses ScreenCaptureKit on macOS 14+, which removes the deprecated CoreGraphics capture path from the primary screenshot workflow.
- the performance and single-instance pass now prevents duplicate BugNarrator launches from staying active at the same time, which reduces the risk of duplicate menu bar items, competing local writes, and overlapping recording state.
- the session library now keeps indexed metadata and direct ID lookups in memory, which reduces filter/search/detail lag as local history grows.

## Remaining Spec-Alignment / Release Notes

These items were reviewed during the release-hardening audit and were left as documented limitations rather than changed in this pass:

- If a user removes or invalidates their OpenAI API key while a recording is already in progress, BugNarrator still does not preserve that finished audio for a later transcription retry. The user must restore the key and record the session again.
