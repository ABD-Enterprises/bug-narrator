#!/usr/bin/env bash
# Refuse to let the owner's notarization identifiers back into the published
# documentation.
#
# The Apple ID, the development team ID, the notary keychain profile name and
# the password-manager item name together tell an attacker exactly which
# credentials to go after. This repository is public, so none of them need to
# be published (AGENTS.md, "Safety: releases and signing").
#
# `scripts/build_dmg.sh` already holds them as the single canonical source of
# truth. This check derives the values from there at run time instead of
# repeating them: the identifiers are never written into this script, into any
# other script, or into any file an agent might copy from one.
#
# The check fails closed. If the canonical values cannot be read, or the
# tracked documentation cannot be listed, it reports the failure rather than
# reporting a clean scan it did not perform.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CANONICAL="$ROOT/scripts/build_dmg.sh"

if [[ ! -f "$CANONICAL" ]]; then
  printf 'FAIL: %s is missing; cannot read the canonical notarization identity\n' "$CANONICAL" >&2
  exit 1
fi

# Reads `NAME="value"` out of the canonical script.
read_default() {
  local name="$1"
  local value
  value="$(sed -n "s/^${name}=\"\(.*\)\"\$/\1/p" "$CANONICAL" | head -1)"
  printf '%s' "$value"
}

TEAM_ID="$(read_default DEFAULT_DEVELOPMENT_TEAM)"
NOTARY_PROFILE="$(read_default DEFAULT_NOTARY_PROFILE)"
APPLE_ID="$(read_default CANONICAL_NOTARY_APPLE_ID)"

MISSING=0
if [[ -z "$TEAM_ID" ]]; then
  printf 'FAIL: could not read DEFAULT_DEVELOPMENT_TEAM from %s\n' "$CANONICAL" >&2
  MISSING=1
fi
if [[ -z "$NOTARY_PROFILE" ]]; then
  printf 'FAIL: could not read DEFAULT_NOTARY_PROFILE from %s\n' "$CANONICAL" >&2
  MISSING=1
fi
if [[ -z "$APPLE_ID" ]]; then
  printf 'FAIL: could not read CANONICAL_NOTARY_APPLE_ID from %s\n' "$CANONICAL" >&2
  MISSING=1
fi
if [[ "$MISSING" -ne 0 ]]; then
  exit 1
fi

# The password-manager item name is built from the profile name, so the
# profile value covers it.
PASSWORD_MANAGER_ITEM="Apple Notarytool - ${NOTARY_PROFILE}"

FAILURES=0

report_hit() {
  local file="$1"
  local line="$2"
  local what="$3"
  printf 'FAIL: %s:%s publishes %s\n' "$file" "$line" "$what" >&2
  FAILURES=1
}

# The tracked documentation is the published surface: root notes, docs/, the
# docs site mirrors and the repository's own templates. Every markdown file
# the repository tracks is scanned, so the identifiers cannot return in a file
# this check does not know about.
DOC_FILES=""
if ! DOC_FILES="$(git ls-files -- '*.md')"; then
  printf 'FAIL: could not list the tracked documentation\n' >&2
  exit 1
fi
if [[ -z "$DOC_FILES" ]]; then
  printf 'FAIL: no tracked documentation was found to scan\n' >&2
  exit 1
fi

# Reports every line of every file that carries a literal identifier.
scan_for_literal() {
  local file="$1"
  local needle="$2"
  local description="$3"

  [[ -n "$needle" ]] || return 0

  local line_number
  while IFS= read -r line_number; do
    [[ -n "$line_number" ]] || continue
    report_hit "$file" "$line_number" "$description"
  done < <(grep -nF -- "$needle" "$file" | cut -d: -f1 || true)
}

# A published command must carry a placeholder, never a live identifier. The
# identifiers are already checked above; this catches the case where a new
# value is written into a doc before anyone rotates the canonical default.
is_placeholder() {
  local value="$1"

  # Angle-bracket placeholders (<team id>) and the YOUR… convention.
  if [[ "$value" == *'<'* || "$value" == *'>'* || "$value" == YOUR* ]]; then
    return 0
  fi

  # A shell expansion (${VAR}, $(cmd)) is a placeholder too.
  if [[ "$value" == '$'* ]]; then
    return 0
  fi

  return 1
}

# Prints the first whitespace-delimited token that follows a flag on a line.
value_after_flag() {
  local file="$1"
  local flag="$2"
  sed -n "s/.*${flag}[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*/\1/p" "$file" | head -1
}

while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  [[ -f "$file" ]] || continue

  scan_for_literal "$file" "$TEAM_ID" "development team ID"
  scan_for_literal "$file" "$NOTARY_PROFILE" "notary keychain profile name"
  scan_for_literal "$file" "$PASSWORD_MANAGER_ITEM" "password-manager item name"
  scan_for_literal "$file" "$APPLE_ID" "notarization Apple ID"

  for flag in "--apple-id" "--team-id" "store-credentials"; do
    value="$(value_after_flag "$file" "$flag")"
    [[ -n "$value" ]] || continue
    if ! is_placeholder "$value"; then
      line_number="$(grep -nF -- "$flag" "$file" | head -1 | cut -d: -f1)"
      report_hit "$file" "${line_number:-?}" "a literal value after '$flag'"
    fi
  done

  for assignment in "DEVELOPMENT_TEAM=" "NOTARY_PROFILE="; do
    value="$(sed -n "s/.*${assignment}\([^[:space:]]\{1,\}\).*/\1/p" "$file" | head -1)"
    [[ -n "$value" ]] || continue
    if ! is_placeholder "$value"; then
      line_number="$(grep -nF -- "$assignment" "$file" | head -1 | cut -d: -f1)"
      report_hit "$file" "${line_number:-?}" "a literal value after '$assignment'"
    fi
  done
done <<<"$DOC_FILES"

if [[ "$FAILURES" -ne 0 ]]; then
  printf '\nDocumentation identifier audit failed.\n' >&2
  exit 1
fi

printf 'PASS: published documentation carries no owner notarization identifiers\n'
