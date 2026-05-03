# Roadmap

This document is historical roadmap context only.

Active planning, backlog, bugs, risks, and remediation now live in [GitHub Issues](https://github.com/deffenda/bugnarrator/issues) through `ai-pipeline`.

Use this file for:

- completed phase history
- high-level product roadmap context
- durable historical notes that should survive issue closure

Do not use this file for:

- current AI task state
- active bug tracking
- active risk tracking
- the live implementation backlog

## Active Work

Use [GitHub Issues](https://github.com/deffenda/bugnarrator/issues) for:

- active bugs such as `BN-*`
- remediation work such as `RR-*`
- Windows milestones such as `WIN-*`
- operational work such as `OPS-*`

The current shipped app version lives in `VERSION` and GitHub Releases.


## Completed Phases

### PF-001 Delivery Foundation Bootstrap

Completed on `2026-03-23`

Scope completed:

- bootstrapped the required structured docs tree
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

### OPS-012 Dependency Alert Remediation

Completed on `2026-04-05`

Scope completed:

- remediated both default-branch Dependabot alert sets across the docs-site dependency graph
- replaced the broken local docs-site npm 11 / Node 25 path with a repo-local Node 22 wrapper
- added direct runtime-guardrails regression tests for the FAIL, NOT RUN, and missing-state-update rules
- verified PR `#6` and PR `#8` merged to `main` and the default-branch Dependabot alert API returned no open alerts

### OPS-010 Retry-Needed Session Filter

Completed on `2026-04-05`

Scope completed:

- added a dedicated `Retry Needed` session-library filter alongside the existing date filters
- routed the recovery banner action into the new filtered view so retryable sessions stay visible in larger histories
- kept retry-needed counts visible in the session-library summary while the new filtered slice is active
- added SessionLibrary regression coverage for retry-needed filtering, counts, and empty-state behavior

## Roadmap Rules

- every unresolved risk should exist as a GitHub issue
- every planned opportunity should exist as a GitHub issue
- `docs/architecture/product-spec.md` is the source of truth for product behavior, terminology, and artifact contracts
- `docs/roadmap/roadmap.md` is the source of truth for historical roadmap context and completed phase history
- GitHub Issues are the source of truth for active AI planning and task state
- `CHANGELOG.md` is the source of truth for shipped change history
