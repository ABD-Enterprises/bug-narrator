# Native macOS + WPF Windows Guidelines

## Purpose
BugNarrator is maintained as two native desktop applications:

- macOS: native SwiftUI/AppKit
- Windows: native WPF/.NET

This is an intentional product strategy. The goal is native reliability, stable workflows, and platform-appropriate behavior, not shared UI code.

## Core Principle
Share the product model, not the UI layer.

Both apps should preserve the same core user workflow where practical:

- record
- capture evidence
- review
- summarize
- extract issues
- export

The apps do not need identical visuals or identical implementation details. They do need workflow parity and compatible artifacts.

## Enforce
- Define a clear product spec.
  - The BugNarrator spec is the source of truth for behavior, terminology, workflows, and feature intent.
  - New work should map back to the spec explicitly.

- Keep data formats stable.
  - Session structure, transcript formats, screenshot metadata, exported bundle contents, and issue payload shapes should remain consistent across platforms.
  - Changes to shared formats must be versioned and documented.

- Keep prompts and templates aligned.
  - OpenAI prompts, summary prompts, issue extraction prompts, export templates, and user-facing wording should stay intentionally aligned unless a platform-specific difference is documented.

- Document parity decisions.
  - When one platform differs, document:
    - what differs
    - why it differs
    - whether the difference is temporary or permanent
  - Maintain an explicit parity note, roadmap entry, or issue record for meaningful differences.

- Separate platform UI from shared domain rules.
  - Business rules, session state rules, export rules, and issue extraction behavior should not live inside SwiftUI views or WPF views.
  - UI should render state and trigger actions, not define core product behavior.

- Accept phased parity.
  - Some features will land on one platform first.
  - That is acceptable if the gap is documented and does not silently become permanent drift.

## Avoid
- Do not duplicate everything blindly.
  - Shared concepts should be defined once in the spec and mirrored deliberately, not reinvented per platform.

- Do not let behavior drift without documentation.
  - If macOS and Windows differ, that difference must be explicit.

- Do not hardcode business rules inside UI layers.
  - Views should not own the recording model, export rules, or issue extraction rules.

- Do not optimize for pixel-perfect parity.
  - Optimize for workflow parity and user clarity.
  - Each platform should still feel native.

## Recommended Architecture
### Platform-Specific Responsibilities
- UI
- tray/menu bar integration
- permissions
- audio capture
- screenshot capture
- hotkeys
- secure credential storage
- packaging and signing

### Shared By Contract And Spec
- session model
- artifact layout
- export formats
- prompt behavior
- review workflow
- issue extraction behavior
- QA expectations
- release standards

## Decision Rule
When making a design choice, ask:

1. Is this a product rule or a platform implementation detail?
2. If it is a product rule, is it documented in the spec?
3. If it differs by platform, is that difference documented?
4. Does this preserve workflow parity, even if the UI differs?

## Definition Of Success
This strategy is working if:

- both apps feel native on their platforms
- testers can follow the same core workflow on both
- exported artifacts are compatible and predictable
- feature differences are intentional and documented
- parity is managed, not guessed
