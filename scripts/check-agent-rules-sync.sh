#!/usr/bin/env bash
# Verify that CLAUDE.md, AGENTS.md, and .agent/rules.md share an identical
# body. The first line of each is allowed (and expected) to differ — it names
# the agent the file is addressed to, e.g. "# Local AI Adapter (Claude)".
# Every line after the first must match across all three, so updates to the
# ORC adapter contract are never lost on one tool while another stays current.
#
# Exits 0 with a one-line PASS message when in sync; exits 1 with a diff
# preview when any pair drifts.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

files=(
  "$ROOT/CLAUDE.md"
  "$ROOT/AGENTS.md"
  "$ROOT/.agent/rules.md"
)

for f in "${files[@]}"; do
  if [[ ! -f "$f" ]]; then
    printf 'FAIL: missing agent rules file: %s\n' "${f#"$ROOT/"}" >&2
    exit 1
  fi
done

reference="${files[0]}"
for f in "${files[@]:1}"; do
  if ! diff -q <(tail -n +2 "$reference") <(tail -n +2 "$f") >/dev/null 2>&1; then
    printf 'FAIL: %s body drift vs %s\n' \
      "${f#"$ROOT/"}" "${reference#"$ROOT/"}" >&2
    printf -- '--- %s\n+++ %s\n' \
      "${reference#"$ROOT/"}" "${f#"$ROOT/"}" >&2
    diff <(tail -n +2 "$reference") <(tail -n +2 "$f") | head -30 >&2
    exit 1
  fi
done

printf 'PASS: CLAUDE.md, AGENTS.md, and .agent/rules.md share identical bodies (only line 1 differs).\n'
