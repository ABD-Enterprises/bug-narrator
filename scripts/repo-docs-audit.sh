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

# The signing and notarization settings live in scripts/build_dmg.sh, and
# AGENTS.md forbids copying them into docs. This repository is public, so a
# doc that names the Apple account, the team or the keychain profile
# publishes them. The values are read from the script rather than written
# here, so the audit does not publish them either.
notary_settings=()
while IFS= read -r setting; do
  [[ -n "$setting" ]] || continue
  notary_settings+=("$setting")
done < <(
  sed -n \
    -e 's/^DEFAULT_DEVELOPMENT_TEAM="\(.*\)"$/\1/p' \
    -e 's/^DEFAULT_NOTARY_PROFILE="\(.*\)"$/\1/p' \
    -e 's/^CANONICAL_NOTARY_APPLE_ID="\(.*\)"$/\1/p' \
    scripts/build_dmg.sh
)

if [[ "${#notary_settings[@]}" -eq 0 ]]; then
  printf 'miss the notary settings in scripts/build_dmg.sh\n' >&2
  FAILURES=1
fi

# Every markdown file the repository publishes, including the site mirror.
mapfile -t published_docs < <(
  printf '%s\n' README.md
  find docs site/docs -name '*.md' -type f 2>/dev/null | sort
)

for setting in "${notary_settings[@]}"; do
  for doc in "${published_docs[@]}"; do
    if grep -Fq -- "$setting" "$doc"; then
      printf 'miss a notarization setting that docs/%s must not publish\n' "$doc" >&2
      FAILURES=1
    fi
  done
done

if [[ "$FAILURES" -ne 0 ]]; then
  echo "Repository docs audit failed." >&2
  exit 1
fi

echo "Repository docs audit passed."
