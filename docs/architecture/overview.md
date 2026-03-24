# Architecture Overview

BugNarrator is a local-first narrated testing tool with a production macOS app and an in-progress native Windows workspace.

The canonical product behavior and terminology contract lives in [product-spec.md](product-spec.md). This overview focuses on implementation shape rather than product requirements.

## Product Model

The product workflow is intentionally stable across platforms:

`record -> review -> refine -> export`

Core product concepts:

- narrated session capture
- screenshot-backed evidence collection
- transcript and summary generation
- extracted issue drafting
- local session history
- optional export to GitHub or Jira

## Repository Layout

- `Sources/BugNarrator`
  macOS app source, SwiftUI/AppKit views, services, models, and utilities
- `Tests/BugNarratorTests`
  macOS-focused unit and integration-style tests
- `windows/`
  Windows MVP workspace and roadmap scaffolding
- `docs/`
  canonical architecture, development, testing, security, release, user, and roadmap docs
- `scripts/`
  local build, smoke-test, packaging, and cleanup automation
- `infra/terraform`
  infrastructure scaffold for future release/distribution automation
- `site/`
  Docusaurus documentation site scaffold

## macOS Runtime Architecture

Key runtime areas in the macOS app:

- `AppState`
  central session, status, and workflow orchestration
- `Services`
  microphone permissions, screen capture permissions, recording, transcription, issue extraction, exports, diagnostics, and persistence
- `Views`
  menu bar UI, recording controls, settings, about/changelog, and review workspace
- `Utilities`
  session library, single-instance control, review-workspace shaping, diagnostics, and metadata helpers

## macOS Data Flow

1. User starts recording from the recording controls window.
2. `MicrophonePermissionService` validates microphone access and recorder readiness.
3. `AudioRecorder` records session audio locally.
4. Screenshot capture is optional during recording and creates both evidence and timeline context.
5. Stopping the session triggers transcription through `TranscriptionClient`.
6. `AppState`, `TranscriptStore`, and related services persist the completed session into local history.
7. The review workspace surfaces transcript, screenshots, extracted issues, and summary.
8. Export services produce local bundles or issue exports on explicit user action.

## Windows Architecture Direction

The Windows implementation is intentionally native rather than cross-platform UI reuse:

- `windows/src/BugNarrator.Core`
  platform-neutral session and workflow models
- `windows/src/BugNarrator.Windows.Services`
  Windows-specific recording, capture, storage, diagnostics, and shell services
- `windows/src/BugNarrator.Windows`
  WPF shell, tray integration, placeholder windows, and overlay wiring

The Windows work follows [docs/CROSS_PLATFORM_GUIDELINES.md](../CROSS_PLATFORM_GUIDELINES.md), [parity-matrix.md](parity-matrix.md), and [windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md](../../windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md).

## Operational Model

BugNarrator is currently distributed as a signed macOS app through GitHub Releases.

- build and packaging are driven by `xcodebuild` plus `scripts/build_dmg.sh`
- release readiness is validated with `scripts/release_smoke_test.sh`
- signed/notarized distribution remains a release-manager workflow, not a cloud-hosted runtime deployment

There is no live backend today. Infrastructure work is therefore focused on release automation, documentation delivery, and future reproducibility rather than service hosting.

## Current Architectural Risks

- Windows WPF runtime behavior has not yet been validated on real Windows hardware
- accessibility validation for the live macOS UI is still heavily manual

These risks are tracked in [docs/roadmap/state.json](../roadmap/state.json) and planned remediation phases in [docs/roadmap/roadmap.md](../roadmap/roadmap.md).
