#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

search_literal() {
  local needle="$1"
  local file="$2"

  if command -v rg >/dev/null 2>&1; then
    rg -q --fixed-strings "$needle" "$file"
  else
    grep -Fq "$needle" "$file"
  fi
}

check_literal() {
  local file="$1"
  local needle="$2"
  local description="$3"

  if search_literal "$needle" "$file"; then
    printf 'ok  %s\n' "$description"
  else
    printf 'miss %s (%s)\n' "$description" "${file#"$ROOT_DIR"/}" >&2
    FAILURES=1
  fi
}

echo "Running BugNarrator accessibility regression checks..."

check_literal \
  "$ROOT_DIR/Sources/BugNarrator/Views/RecordingControlPanelView.swift" \
  '.keyboardShortcut(.defaultAction)' \
  'recording controls default action keyboard shortcut'
check_literal \
  "$ROOT_DIR/Sources/BugNarrator/Views/RecordingControlPanelView.swift" \
  '.keyboardShortcut(.cancelAction)' \
  'recording controls cancel keyboard shortcut'
check_literal \
  "$ROOT_DIR/Sources/BugNarrator/Views/RecordingControlPanelView.swift" \
  'announcementRequested' \
  'recording toast accessibility announcement'
check_literal \
  "$ROOT_DIR/Sources/BugNarrator/Views/TranscriptView.swift" \
  '.accessibilityAddTraits(selectedFilter == filter ? .isSelected : [])' \
  'session-library filter selected-state announcement'
check_literal \
  "$ROOT_DIR/Sources/BugNarrator/Views/TranscriptView.swift" \
  '.accessibilityAddTraits(.isHeader)' \
  'review workspace section heading announcement'
check_literal \
  "$ROOT_DIR/Sources/BugNarrator/Views/TranscriptView.swift" \
  'Select issue ' \
  'issue export checkbox labeling'
check_literal \
  "$ROOT_DIR/Sources/BugNarrator/Views/SettingsView.swift" \
  'accessibilityLabel: "OpenAI API Key"' \
  'settings API key label'
check_literal \
  "$ROOT_DIR/Sources/BugNarrator/Views/SettingsView.swift" \
  '.accessibilityLabel("Jira issue type")' \
  'settings Jira issue type label'
check_literal \
  "$ROOT_DIR/Sources/BugNarrator/Views/MenuBarView.swift" \
  '.accessibilityHint("Opens the recording controls window.")' \
  'menu bar recording controls hint'
check_literal \
  "$ROOT_DIR/Sources/BugNarrator/Views/MenuBarView.swift" \
  '.accessibilityLabel("Open Microphone privacy settings")' \
  'menu bar microphone recovery label'
check_literal \
  "$ROOT_DIR/Sources/BugNarrator/Views/HotkeyRecorderView.swift" \
  'Assign") shortcut for ' \
  'hotkey recorder assignment label'
check_literal \
  "$ROOT_DIR/Sources/BugNarrator/Views/HotkeyRecorderView.swift" \
  'Clear shortcut for ' \
  'hotkey recorder clear label'

if [[ "$FAILURES" -ne 0 ]]; then
  echo "Accessibility regression checks failed." >&2
  exit 1
fi

echo "Accessibility regression checks passed."
