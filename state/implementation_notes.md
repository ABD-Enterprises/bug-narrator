# Implementation Notes

task_id: N1
status: ready_for_review

CHANGED:
- Sources/BugNarrator/AppState.swift
- Sources/BugNarrator/Services/IssueExtractionService.swift
- Sources/BugNarrator/Views/SettingsView.swift
- Sources/BugNarrator/Views/TranscriptView.swift
- Tests/BugNarratorTests/AppStateTests.swift
- Tests/BugNarratorTests/IssueExtractionServiceTests.swift
- Tests/BugNarratorTests/MenuBarStatusPresentationTests.swift

DID:
- Forced completed recording sessions to persist locally on stop, even if the legacy auto-save preference is disabled.
- Added staged progress text for stop and retry flows so transcription, local save, and extraction progress are visible as text.
- Enforced a 10-second issue-extraction timeout with a clear retry/faster-model error.
- Reworked the review pane into one stacked workspace so summary, extracted issues, screenshots, and transcript are visible in a single view.
- Updated workflow settings copy to reflect required local session persistence.

VALIDATED:
- ./scripts/validate.sh 314d332a132e94f9076d7da5c512d031f598a7ff
- xcodebuild -project BugNarrator.xcodeproj -scheme BugNarrator -configuration Debug CODE_SIGNING_ALLOWED=NO test

NEXT:
- Review the unified transcript workspace and the forced auto-save behavior in PR review.
