#!/usr/bin/env bash
# Verify the agent-file layout of the fleet standard: AGENTS.md is the one
# canonical copy of the agent rules, CLAUDE.md contains exactly the line
# "@AGENTS.md" (an import, so there is nothing to drift), and
# .agent/rules.md is a short pointer that names AGENTS.md.
#
# Exits 0 with a one-line PASS message when the layout holds; exits 1 with the
# reason otherwise.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for f in AGENTS.md CLAUDE.md .agent/rules.md; do
  if [[ ! -f "$ROOT/$f" ]]; then
    printf 'FAIL: missing agent rules file: %s\n' "$f" >&2
    exit 1
  fi
done

if [[ "$(tr -d '[:space:]' < "$ROOT/CLAUDE.md")" != "@AGENTS.md" ]]; then
  printf 'FAIL: CLAUDE.md must contain only the line "@AGENTS.md"\n' >&2
  exit 1
fi

if ! grep -Fq 'AGENTS.md' "$ROOT/.agent/rules.md"; then
  printf 'FAIL: .agent/rules.md must point at AGENTS.md\n' >&2
  exit 1
fi

printf 'PASS: CLAUDE.md imports AGENTS.md and .agent/rules.md points at it.\n'
