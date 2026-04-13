# Tasks

## Phase 1: Core Polish + Reproduction Steps

### N1
Title: End-to-end recording flow hardening
Status: done
Phase: 1
Description: Ensure the core flow is bulletproof: start recording → narrate → capture screenshots → stop → transcribe → extract issues → review → export. Fix any rough edges in the current flow. Recording must handle microphone permission gracefully (prompt, not crash). Transcription must show progress as text. Issue extraction must complete within 10 seconds of transcription finishing. Session must auto-save on stop (no data loss if app quits). Review screen must show transcript + screenshots + extracted issues in one view without scrolling between tabs.
Done when: Full record → transcribe → extract → export flow works without errors. Mic permission handled. Progress shown. Auto-save works. Review shows everything in one view.

---

### N2
Title: AI-generated reproduction steps from narration + screenshots
Status: done
Phase: 1
Depends on: N1
Description: After issue extraction, generate step-by-step reproduction instructions for each extracted issue. AI analyzes the narration timeline (what was said when) + screenshot timestamps (what was visible) to produce numbered steps: "1. Navigate to X. 2. Click Y. 3. Enter Z. Expected: A. Actual: B." Reproduction steps appear on each extracted issue in the review screen. Editable before export. Include the relevant screenshot reference per step. This is the killer differentiator — no tool generates repro steps from narration.
Done when: Each extracted issue has AI-generated reproduction steps. Steps reference specific timestamps and screenshots. Editable in review screen. Exported with the issue to Jira/GitHub.

---

### N3
Title: Enhanced issue classification — severity, component, deduplication hint
Status: done
Phase: 1
Depends on: N1
Description: Enhance AI issue extraction to include: severity assessment (critical/high/medium/low based on narration tone and content — "this is completely broken" → critical, "minor visual glitch" → low), suggested component/area (based on screenshots and narration context — "Settings > Accounts" or "Login Page"), and a deduplication hint (hash of the issue description for later duplicate detection). Show severity and component on each issue in the review screen. Editable before export.
Done when: Issues have severity, component, and dedup hint. Severity inferred from narration. Component inferred from screenshots/context. All editable.

---

### N3-H1
Title: Deduplication hash locale stability and extraction inference optimization
Status: done
Phase: 1
Depends on: N3
Description: Address two post-review hardening items from N3: (1) Fix string folding in deduplication hint generation to use a fixed locale (e.g., `.current` pinned or explicit `.en_US_POSIX`) so that hashes are stable across machines and user locales — a locale-dependent hash breaks duplicate detection when sessions are shared across team members. (2) Move severity-heuristic signal arrays in `IssueExtractionService` to static constants so they are allocated once rather than on every inference call. Both changes are non-functional from a feature standpoint but are correctness and performance prerequisites for N5 (duplicate detection).
Done when: Deduplication hints generate identical hashes for identical input across all locales. Severity signal arrays are static constants in `IssueExtractionService`. Existing tests pass.

---

## Phase 2: Smart Features

### N4
Title: Smart screenshot annotation — auto-highlight relevant UI elements
Status: done
Phase: 2
Depends on: N2
Description: When the tester narrates about a specific UI element ("this button doesn't respond"), AI analyzes the screenshot to identify and annotate the element being discussed. Draw a subtle highlight box or arrow pointing to the relevant UI area. Annotation appears in the review screen overlay on the screenshot. Tester can adjust or remove annotations. Annotated screenshots export with the issue. Uses vision model (GPT-4o or similar) to locate UI elements from narration context.
Done when: Screenshots auto-annotated with highlights matching narration. Annotations editable. Annotated versions export with issues. Vision model identifies correct UI elements.

---

### N5
Title: Similar bug detection before export
Status: pending
Phase: 2
Depends on: N3
Description: Before exporting an issue to Jira or GitHub, check existing open issues for potential duplicates or related bugs. Query the issue tracker API for open issues with similar titles/descriptions. AI compares the new issue against top matches and shows: "This may be related to PROJ-142 (85% match): Login form validation broken." User can link as related, mark as duplicate, or export as new. Reduces duplicate tickets filed. Works with both Jira and GitHub Issues.
Done when: Pre-export duplicate check queries Jira/GitHub. AI matches shown with confidence. User can link, mark duplicate, or proceed. Works for both trackers.

---

### N6
Title: Session intelligence — testing coverage summary
Status: pending
Phase: 2
Depends on: N1
Description: After a recording session, AI generates a testing coverage summary: what areas/features were tested (from narration + screenshots), how many issues found by severity, what was NOT tested (inferred from app structure if available, or stated gaps). Summary shown at the top of the review screen. Exportable as a testing report (markdown). Product managers use this to understand what QA covered in a session without watching recordings.
Done when: Session summary generated after recording. Shows tested areas, issue counts, coverage gaps. Exportable as markdown. Visible in review screen header.

---

## Phase 3: Team + Enterprise

### N7
Title: Shared session library — team access to recorded sessions
Status: pending
Phase: 3
Depends on: N1
Description: Share recorded sessions with team members. Sessions stored in a shared location (iCloud folder, shared drive, or team server). Session library shows all team sessions in a sortable table: tester, date, app/feature tested, issue count, duration. Filter by tester, date range, app area. Click to open and review any session. Permissions: team members can view, only the recorder can edit/delete. Session metadata synced; full recordings fetched on demand.
Done when: Shared session library shows team sessions. Table sortable/filterable. View permissions work. On-demand fetch for full recordings.

---

### N8
Title: Enterprise SSO and API key management
Status: pending
Phase: 3
Depends on: N7
Description: Support enterprise authentication: SSO via OIDC/SAML for team access. Centralized OpenAI API key management — admin sets the key once, all team members use it without seeing it. API usage tracking per user. Key stored in enterprise keychain or vault, never on individual machines. Admin settings view for key management and usage dashboard (table, not cards).
Done when: SSO login works via OIDC. Centralized API key set by admin. Usage tracking per user. Key never exposed to individual machines.

---

### N9
Title: Session analytics — team testing velocity and coverage trends
Status: pending
Phase: 3
Depends on: N6, N7
Description: Aggregate session intelligence across the team: sessions per week, issues found per session trend, coverage by app area over time, top bug categories. Shown as compact summary text and sortable tables (not dashboard charts). "This week: 23 sessions, 47 issues found, 12 critical. Most tested: Settings (8 sessions). Least tested: Billing (0 sessions)." Helps QA leads identify coverage gaps and testing velocity trends.
Done when: Team analytics aggregates session data. Summary text with key metrics. Tables for drill-down. Coverage gaps identified. No dashboard/chart treatment.
