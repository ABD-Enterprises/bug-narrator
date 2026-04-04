# BugNarrator Product Spec

This is the canonical BugNarrator product specification.

Use this document as the source of truth for:

- product behavior
- workflow and terminology
- user-facing surfaces
- artifact and export contracts
- credential, permission, privacy, and accessibility expectations
- cross-platform parity expectations

Do not use this document as the source of truth for:

- roadmap execution state or risk planning
- release history
- platform-specific implementation details

Those live in:

- [docs/roadmap/state.json](../roadmap/state.json) for delivery state, risks, incidents, and planned phases
- [docs/roadmap/roadmap.md](../roadmap/roadmap.md) for the human-readable roadmap
- [CHANGELOG.md](../../CHANGELOG.md) for shipped change history
- [parity-matrix.md](parity-matrix.md) for deliberate cross-platform parity decisions
- platform implementation docs such as [windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md](../../windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md) for Windows-specific execution details

## Product Identity

BugNarrator is a local-first desktop tool for narrated software testing and software review.

Its durable product workflow is:

`record -> review -> refine -> export`

BugNarrator is designed so a tester can keep using the target app while narrating what they are doing, what they expected, and what actually happened.

## Product Status

Current shipped product scope:

- production app: macOS menu bar application
- production distribution: signed macOS DMG through GitHub Releases

In-progress platform work:

- native Windows implementation in the `windows/` workspace

The Windows work must preserve this product specification unless a platform-specific parity decision is documented.

## Target Users And Jobs To Be Done

Primary users:

- manual testers
- developers doing narrated verification passes
- product and design reviewers
- maintainers collecting high-quality repro artifacts

Core jobs:

- record a narrated testing session without stopping to type notes
- capture visual evidence at meaningful moments
- turn the session into a searchable local review artifact
- refine extracted issues before export
- export a portable session bundle or selected issues when needed

## Supported Platforms And Scope Boundaries

Current supported production platform:

- macOS 14 or later

Current scope boundaries:

- no backend or cloud sync
- no live dictation into the frontmost app
- no automatic telemetry or remote log collection
- no system audio capture
- no requirement for Accessibility permission in the core workflow

## Core Workflow And Canonical Terminology

The canonical workflow is:

1. `Record`
2. `Review`
3. `Refine`
4. `Export`

Canonical product terms:

- `Menu Bar Window`
  the compact status and launch surface shown from the macOS menu bar item
- `Recording Controls`
  the persistent window used to start recording, stop recording, and capture screenshots
- `Session Library`
  the archive of recorded sessions with search, filtering, sorting, review, and deletion
- `Review Workspace`
  the right-hand session detail area inside the session library
- `Timeline Event`
  a timestamped transcript or screenshot-linked event shown during review
- `Review Summary`
  the concise synthesized summary for a session
- `Extracted Issues`
  draft bugs, UX issues, enhancements, and follow-up items derived from the session
- `Session Bundle`
  the portable local export containing `transcript.md` and `screenshots/`
- `Debug Bundle`
  the support-focused diagnostics export that intentionally excludes raw credentials

## Primary Product Surfaces

### Menu Bar Window

The menu bar window is the compact launch and recovery surface.

It must provide:

- current session status
- recovery guidance when permissions, credentials, or storage block progress
- access to `Show Recording Controls`
- access to `Open Session Library`
- access to settings, documentation, changelog, support, issue reporting, and updates

`Export Debug Bundle` is a support action, not a primary workflow action. It is intentionally hidden behind `Option` in the menu bar.

### Recording Controls

The recording controls window is the primary live-session control surface.

It must provide:

- `Start Recording`
- `Stop Recording`
- `Capture Screenshot`
- `Close`

The window remains open until the user closes it.

Global hotkeys are optional and start unassigned by default.

### Session Library And Review Workspace

The session library is the durable archive for recorded sessions.

It must support:

- date filters: `Today`, `Yesterday`, `Last 7 Days`, `Last 30 Days`, `Retry Needed`, `All Sessions`, and `Custom Date Range`
- search across session metadata and reviewable content
- newest-first and oldest-first sorting
- inline selection and review without opening a separate transcript popup
- permanent deletion of saved sessions

The review workspace is the selected-session detail surface. Its canonical tabs are:

- `Transcript`
- `Screenshots`
- `Extracted Issues`
- `Summary`

If issue extraction returns no draft issues, the review flow must fall back to `Summary` instead of leaving an empty extracted-issues view selected.

### Settings

Settings owns:

- OpenAI credential setup
- transcription defaults
- issue-extraction defaults
- workflow defaults
- launch-at-login preference
- permission guidance
- optional hotkey assignment
- experimental GitHub and Jira export configuration
- diagnostics snapshot information

### About / Changelog / Support

BugNarrator includes product-information surfaces for:

- About
- What’s New / changelog
- documentation
- issue reporting
- support development
- release-page updates

## Session Lifecycle And Recovery Rules

### Recording

BugNarrator records microphone audio in the background while the tester continues working in other apps.

The app must:

- prevent overlapping recording sessions
- avoid fake recording states when microphone setup fails
- keep screenshot capture from interrupting audio recording
- remain single-instance so duplicate app launches do not create competing session state

### Transcription

BugNarrator generates transcripts after recording ends.

It does not continuously stream live audio to OpenAI while the user is still recording.

### Recovery

If the OpenAI key is missing, invalid, or revoked when a session finishes recording:

- the completed session must remain preserved locally
- the library must expose that the session needs transcription retry
- the user must be able to restore or replace the key and retry transcription later

### Legacy Compatibility

Older sessions with legacy standalone marker data must remain readable in the current review and export flow.

## Evidence Capture Contract

### Narration

BugNarrator is optimized for short, factual spoken narration during live testing.

The tester narration guidance is part of the supported workflow because better narration improves:

- transcript quality
- issue extraction quality
- screenshot correlation
- follow-up AI prompts for fixes

### Screenshot Capture

Screenshots are explicit user actions, not continuous capture.

Current macOS product behavior:

- screenshot capture is available only during an active session
- screenshot capture uses a drag-select overlay on macOS 14+
- `Esc` cancels screenshot selection without ending the recording
- each saved screenshot is attached to the active session
- each saved screenshot creates a linked timeline event at the same timestamp

## Review Workspace And Session Library Contract

The review experience must let the user inspect and refine a session before export.

The transcript view must preserve readable timestamped events.

The screenshots view must act as both:

- visual evidence list
- important-moments index

Extracted issues are drafts:

- they remain editable before export
- they preserve transcript evidence and timestamp context when available
- selection state for export must persist while the user refines them

The session library is an archive of review sessions, not only a transcript list.

Deleting a session:

- removes it from the local library
- removes managed local screenshot files for that session
- does not remove files the user already exported outside BugNarrator

## Export And Artifact Contract

### Session Bundle

The canonical session bundle export contains:

- `transcript.md`
- `screenshots/`

### Issue Export

BugNarrator supports selected-issue export to:

- GitHub Issues
- Jira Cloud

These integrations are explicitly experimental in the current product.

### Debug Bundle

The debug bundle is a support artifact.

It may include:

- app and macOS version information
- recent local logs
- safe session metadata

It must not include:

- raw OpenAI keys
- raw GitHub tokens
- raw Jira tokens
- other raw credentials

## Credentials, Permissions, And Privacy Model

### Credentials

BugNarrator does not ship with a built-in OpenAI API key.

Users must provide their own credentials for:

- OpenAI transcription and issue extraction
- GitHub export
- Jira export

Credential expectations:

- store secrets in secure platform storage when available
- otherwise keep them only for the active run
- never bundle them in source code, logs, debug bundles, or release artifacts

### Permissions

BugNarrator requests permissions only when required by the user action.

Current product behavior:

- microphone permission is requested when starting recording
- screen-recording permission is requested when capturing screenshots
- screenshot permission failure does not invalidate the recording session
- Accessibility permission is not required for the core workflow

### Privacy And Data Handling

Data that remains local unless the user explicitly exports it:

- session history
- transcript results returned from OpenAI
- screenshots and screenshot metadata
- extracted issue drafts
- debug bundles
- session bundles

Data sent off-device only when the user invokes the relevant workflow:

- recorded audio for OpenAI transcription
- transcript context for summary or issue extraction
- selected issue payloads for GitHub or Jira export

BugNarrator does not include automatic telemetry or remote log shipping.

## Accessibility Contract

BugNarrator must support keyboard-first use across the core product surfaces.

At minimum, the product contract requires:

- keyboard navigation across the menu bar window, recording controls, session library, review workspace, and settings
- visible and logical focus behavior
- explicit labels for controls that are not self-describing from visible text alone
- selected-state semantics for custom filters, tabs, and selection controls
- meaningful status and feedback announcements for transient but important workflow changes
- readable error and recovery messaging

Validation remains partly manual, but these expectations are product requirements, not optional polish.

## Experimental Features, Limitations, And Parity Notes

Current experimental areas:

- GitHub issue export
- Jira issue export

Current platform parity note:

- macOS is the shipped product today
- Windows is an in-progress native implementation that must preserve this spec’s workflow, terminology, and artifact contracts unless an explicit parity decision says otherwise

Cross-platform decisions must also follow [docs/CROSS_PLATFORM_GUIDELINES.md](../CROSS_PLATFORM_GUIDELINES.md).
