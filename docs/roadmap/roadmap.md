# Roadmap

This document is the human-readable roadmap companion to [state.json](state.json).

## Current Status

- current production app version: `1.0.22`
- latest completed phase in this run: `OPS-007 Release Summary Automation Seed`
- phase outcome: five local non-release phases completed with build, test, workflow, docs-site, and state validation, and not released as a new app version

## Completed Phases

### PF-001 Delivery Foundation Bootstrap

Completed on `2026-03-23`

Scope completed:

- bootstrapped the required structured docs tree
- created persistent roadmap state in `docs/roadmap/state.json`
- added CI and release workflow scaffolding
- added Terraform scaffolding for future distribution automation
- added a Docusaurus site scaffold
- mapped existing docs into the new structured hierarchy without deleting working detailed docs

### RR-001 macOS Session Recovery Hardening

Completed on `2026-03-23`

Scope completed:

- preserved finished recordings when transcription cannot start because the OpenAI key is missing, invalid, or revoked at stop time
- stored retryable session metadata in the session library so recovery stays visible in the existing review workflow
- added retry-transcription actions and disabled transcript-only actions until a preserved session is successfully transcribed
- removed preserved retry audio after successful retry in normal mode so the fix does not expand raw-audio retention unnecessarily
- added regression coverage for preserved-session persistence, retry success, and review-workspace recovery rendering

### RR-003 Accessibility Audit And Interaction Hardening

Completed on `2026-03-23`

Scope completed:

- added explicit accessibility labels, values, and hints for previously unlabeled issue-export controls, screenshot actions, hotkey controls, and settings fields
- improved keyboard-first affordances in the recording controls window with default and cancel actions
- made session-library filters, custom review tabs, and session rows announce clearer selected-state and summary information
- added macOS accessibility announcements for transient recording toasts
- updated testing, QA, release, and user docs to reflect the new accessibility baseline and remaining manual validation work

### RR-004 Product Spec Consolidation

Completed on `2026-03-23`

Scope completed:

- created a single canonical product spec under `docs/architecture/product-spec.md`
- clarified the boundary between product truth, roadmap state, and release history
- updated maintainer, roadmap, release, security, testing, and Windows-planning docs to reference the canonical product spec directly
- removed the last repo-level references that treated an implied spec or the current macOS implementation as the product contract

### OPS-003 Recovery Surface Polish

Completed on `2026-03-23`

Scope completed:

- surfaced retry-needed sessions in the menu bar window so preserved-session recovery stays visible after relaunch
- added a retry-needed banner at the top of the session-library list
- added retry-needed counts to the library header summary

### OPS-004 Accessibility Automation Seed

Completed on `2026-03-23`

Scope completed:

- added `./scripts/accessibility_regression_check.sh` as a lightweight accessibility regression tripwire
- wired the new script into CI and release workflow scaffolding
- documented the boundary between the new automation seed and the remaining live assistive-technology validation work

### OPS-005 Spec-Driven Parity Matrix

Completed on `2026-03-23`

Scope completed:

- created `docs/architecture/parity-matrix.md`
- mapped platform parity back to named product-spec contracts
- linked architecture, cross-platform, and Windows-planning docs to the parity matrix

### OPS-006 Docs Site Sync And Build Validation

Completed on `2026-03-23`

Scope completed:

- synced the Docusaurus site to the canonical onboarding, user-manual, and product-spec content
- fixed the site shell routing and favicon configuration
- generated a site lockfile and validated a strict production site build locally
- added docs-site build validation to CI

### OPS-007 Release Summary Automation Seed

Completed on `2026-03-23`

Scope completed:

- added `scripts/generate_release_summary.py`
- wired the generated summary into the release workflow as a run summary and artifact
- documented the summary as a maintainer aid rather than a public release-note replacement

## Risk Remediation Phases

### RR-002 Windows Runtime Validation And Hardening

Priority: High

Grouped risks:

- WPF tray, recording, and screenshot milestones have not yet been validated on real Windows
- CI and runtime confidence for Windows remain lower than macOS

### RR-005 Assistive Technology Runtime And Docs Validation

Priority: Low

Grouped risks:

- a real VoiceOver-driven runtime pass and docs-site accessibility validation still need to be run once the site is published and release-candidate UI is exercised live

## Upcoming Feature / Opportunity Phases

### WIN-005 Windows Transcription And Session Library

Expected value: High
Effort: High

### WIN-006 Windows Review, Extraction, And Export

Expected value: High
Effort: High

### OPS-008 Docs Site Publication

Expected value: Medium
Effort: Medium

### OPS-009 Release Summary Promotion

Expected value: Medium
Effort: Low

### OPS-010 Retry-Needed Session Filter

Expected value: Medium
Effort: Low

## Roadmap Rules

- every unresolved risk must belong to a remediation phase
- every opportunity must belong to a future phase
- `docs/architecture/product-spec.md` is the source of truth for product behavior, terminology, and artifact contracts
- roadmap state in `state.json` is the source of truth for planning, risks, incidents, and phase status
- `CHANGELOG.md` is the source of truth for shipped change history
