# Product Spec

This page mirrors the canonical BugNarrator product spec at a high level.

The full authoritative version lives in the repository at [docs/architecture/product-spec.md](https://github.com/deffenda/bugnarrator/blob/main/docs/architecture/product-spec.md).

## Product Identity

BugNarrator is a local-first desktop tool for narrated software testing and software review.

Its durable workflow is:

`record -> review -> refine -> export`

## Primary Product Surfaces

- `Menu Bar Window`
  the compact status and recovery surface on macOS
- `Recording Controls`
  start, stop, screenshot, and close
- `Session Library`
  the durable archive of recorded sessions
- `Review Workspace`
  transcript, screenshots, extracted issues, and summary
- `Session Bundle`
  `transcript.md` plus `screenshots/`
- `Debug Bundle`
  support diagnostics export that excludes raw credentials

## Core Product Rules

- only one recording session can be active at a time
- screenshot capture should not interrupt audio recording
- finished sessions must remain recoverable if transcription is blocked by missing or invalid credentials
- issue export to GitHub and Jira remains experimental
- exported artifacts stay local and understandable

## Platform Direction

- macOS is the current production platform
- Windows is being built as a native WPF app in the `windows/` workspace
- workflow parity matters more than pixel-perfect UI parity

## Related Docs

- [Cross-Platform Guidelines](https://github.com/deffenda/bugnarrator/blob/main/docs/CROSS_PLATFORM_GUIDELINES.md)
- [Cross-Platform Parity Matrix](https://github.com/deffenda/bugnarrator/blob/main/docs/architecture/parity-matrix.md)
- [Windows Implementation Roadmap](https://github.com/deffenda/bugnarrator/blob/main/windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md)
