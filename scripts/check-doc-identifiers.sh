#!/usr/bin/env bash
# Refuse to let the owner's notarization identifiers back into the published
# surface of this public repository.
#
# The Apple ID, the development team ID, the notary keychain profile name and
# the password-manager item name together tell an attacker exactly which
# credentials to go after. None of them needs to be public (AGENTS.md, "Safety:
# releases and signing").
#
# `scripts/build_dmg.sh` holds them as the canonical source of truth. This
# check derives the values from there at run time instead of repeating them:
# the identifiers are never written into this script, into any other script,
# or into any file an agent might copy from one.
#
# The check scans every tracked text file, not just the documentation, because
# the identifiers were published in a doc once and can be published in any
# tracked file the next time. A short allowlist names the few places that
# legitimately hold a value, each with the reason it holds it.
#
# The check fails closed. If the canonical values cannot be read, or the
# tracked files cannot be listed, it reports the failure rather than
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

# The places that legitimately hold an identifier, and why. Everything else
# tracked in the repository must be free of them.
#
# The team ID is disclosed by the published artifact itself — `spctl -a -vv`
# prints it for any signed release — so it is not a secret in itself. It is
# still kept out of the published documentation, where it would narrow an
# attacker on the Apple ID, the notary profile and the password-manager item
# that sit next to it.
#
#   scripts/build_dmg.sh                          the canonical defaults
#   Sources/.../LocalTranscriptionManager.swift  the publisher requirement the
#                                                app verifies the downloaded
#                                                server against
#
# The recorded clauses of closed tickets are not on the list: an archived
# done_when clause that names the team is a published copy of it, and it is
# scrubbed like any other.
ALLOWED_TEAM_ID=(
  "scripts/build_dmg.sh"
  "Sources/BugNarrator/Services/LocalTranscriptionManager.swift"
)

# The Apple ID, the notary profile name and the password-manager item name
# name the credentials themselves, so only the canonical script may hold them.
ALLOWED_CREDENTIAL=(
  "scripts/build_dmg.sh"
)

# A path is allowed for an identifier when it is that identifier's file, or
# inside one of its directories.
path_allowed_for() {
  local file="$1"
  shift
  local allowed
  for allowed in "$@"; do
    [[ "$file" == "$allowed" ]] && return 0
    [[ "$file" == "$allowed"/* ]] && return 0
  done
  return 1
}

FAILURES=0

report_hit() {
  local file="$1"
  local line="$2"
  local what="$3"
  if [[ -n "$line" ]]; then
    printf 'FAIL: %s:%s publishes %s\n' "$file" "$line" "$what" >&2
  else
    printf 'FAIL: %s publishes %s\n' "$file" "$what" >&2
  fi
  FAILURES=1
}

# The tracked files are the published surface: every file in this public
# repository is world-readable, so the identifiers must stay out of all of
# them, not only out of the documentation.
TRACKED_FILES=""
if ! TRACKED_FILES="$(git ls-files)"; then
  printf 'FAIL: could not list the tracked files\n' >&2
  exit 1
fi
if [[ -z "$TRACKED_FILES" ]]; then
  printf 'FAIL: no tracked files were found to scan\n' >&2
  exit 1
fi

# Reports every line of a file that carries a literal identifier. A file is
# skipped for an identifier only when it is on that identifier's allowlist.
#
# The values compared here are the canonical ones read from
# scripts/build_dmg.sh at run time. A value that was published and then
# rotated out of the canonical script is not among them, so this check finds
# the current identity, not every identity that was ever published.
#
# The match is case-insensitive. The Apple ID is a mailbox, and a mailbox is
# reachable at any case, so a differently-cased spelling of it is the same
# account and a case-sensitive check would wave it through. The team ID and
# the profile name are case-insensitive for the same reason: a copy of the
# value that has been retyped in a different case is still the value.
scan_for_literal() {
  local file="$1"
  local needle="$2"
  local description="$3"

  [[ -n "$needle" ]] || return 0

  local line_number
  while IFS= read -r line_number; do
    [[ -n "$line_number" ]] || continue
    report_hit "$file" "$line_number" "$description"
  done < <(grep -niIF -- "$needle" "$file" 2>/dev/null | cut -d: -f1 || true)

  # A binary file that matches has no useful line number, but it is still a
  # published copy and must not be reported as clean.
  if grep -qilF -- "$needle" "$file" 2>/dev/null && ! grep -qiIF -- "$needle" "$file" 2>/dev/null; then
    report_hit "$file" "" "$description"
  fi
}

# A published command must carry a placeholder, never a live identifier. The
# canonical identifiers are already checked above; this catches the case
# where a different value is written into a tracked file.
is_placeholder() {
  local value="$1"

  # Strip surrounding quotes so a quoted expansion is recognised.
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"

  # Angle-bracket placeholders (<team id>) and the YOUR… convention, matched
  # case-insensitively so that `your-team-id` is read as the placeholder it is.
  local lowered="${value,,}"
  if [[ "$lowered" == *'<'* || "$lowered" == *'>'* || "$lowered" == your* ]]; then
    return 0
  fi

  # A shell expansion (${VAR}, $(cmd)) is a placeholder too.
  if [[ "$value" == '$'* ]]; then
    return 0
  fi

  return 1
}

# Prints "line<TAB>value" for every occurrence of a flag in a file, resolving
# a shell line continuation so that a value on the next line is found too.
flag_values() {
  local file="$1"
  local flag="$2"

  local line lineno content rest value
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    lineno="${line%%:*}"
    content="${line#*:}"

    rest="${content#*"$flag"}"
    rest="${rest#"${rest%%[![:space:]]*}"}"

    if [[ "$rest" == "\\" || "$rest" == "\\ "* ]]; then
      # The value is on the following line.
      value="$(sed -n "$((lineno + 1))p" "$file")"
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%%[[:space:]]*}"
    else
      value="${rest%%[[:space:]]*}"
    fi

    [[ -n "$value" ]] || continue
    printf '%s\t%s\n' "$lineno" "$value"
  done < <(grep -nIF -- "$flag" "$file" 2>/dev/null || true)
}

while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  [[ -f "$file" ]] || continue

  # The literal identifiers are checked across the whole tracked tree: every
  # file in this public repository is world-readable.
  if ! path_allowed_for "$file" "${ALLOWED_TEAM_ID[@]}"; then
    scan_for_literal "$file" "$TEAM_ID" "development team ID"
  fi
  if ! path_allowed_for "$file" "${ALLOWED_CREDENTIAL[@]}"; then
    scan_for_literal "$file" "$NOTARY_PROFILE" "notary keychain profile name"
    scan_for_literal "$file" "$PASSWORD_MANAGER_ITEM" "password-manager item name"
    scan_for_literal "$file" "$APPLE_ID" "notarization Apple ID"
  fi

  # The "a published command must carry a placeholder" rule applies to the
  # documentation, where a reader copies a command from. A source file is
  # allowed to hold its own defaults — that is what a default is — so this
  # check is scoped to the markdown the repository publishes.
  case "$file" in
    *.md) ;;
    *) continue ;;
  esac

  for flag in "--apple-id" "--team-id" "store-credentials"; do
    while IFS=$'\t' read -r lineno value; do
      [[ -n "$value" ]] || continue
      if ! is_placeholder "$value"; then
        report_hit "$file" "$lineno" "a literal value after '$flag'"
      fi
    done < <(flag_values "$file" "$flag")
  done

  for assignment in "DEVELOPMENT_TEAM=" "NOTARY_PROFILE="; do
    while IFS=$'\t' read -r lineno value; do
      [[ -n "$value" ]] || continue
      if ! is_placeholder "$value"; then
        report_hit "$file" "$lineno" "a literal value after '$assignment'"
      fi
    done < <(flag_values "$file" "$assignment")
  done
done <<<"$TRACKED_FILES"

if [[ "$FAILURES" -ne 0 ]]; then
  printf '\nDocumentation identifier audit failed.\n' >&2
  exit 1
fi

printf 'PASS: the published surface carries no owner notarization identifiers\n'
