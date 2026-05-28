#!/usr/bin/env bash
# Checks that maintainer-facing docs keep pointing at the canonical local
# validation path instead of drifting back to ad hoc or CI-expensive commands.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FAILURES=0

require_literal() {
  local file="$1"
  local needle="$2"
  local description="$3"

  if grep -Fq -- "$needle" "$file"; then
    printf 'ok  %s\n' "$description"
  else
    printf 'miss %s (%s)\n' "$description" "$file" >&2
    FAILURES=1
  fi
}

require_literal \
  "README.md" \
  "./scripts/validate.sh origin/main" \
  "README names the cheap local-first validator"

require_literal \
  "docs/development/setup.md" \
  "./scripts/validate.sh origin/main" \
  "development setup names the cheap local-first validator"

require_literal \
  "docs/testing/testing.md" \
  "./scripts/validate.sh origin/main" \
  "testing guide names the cheap local-first validator"

require_literal \
  "docs/testing/testing.md" \
  "-only-testing:BugNarratorTests" \
  "testing guide documents the CI-aligned unit-test scope"

require_literal \
  ".github/workflows/ci.yml" \
  "./scripts/validate.sh" \
  "CI uses the same validator named in docs"

if [[ "$FAILURES" -ne 0 ]]; then
  echo "Repository docs audit failed." >&2
  exit 1
fi

echo "Repository docs audit passed."
