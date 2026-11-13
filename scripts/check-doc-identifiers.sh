#!/usr/bin/env bash
# Refuse to let the owner's notarization identifiers back into the published
# surface of this public repository.
#
# The signing and notarization settings do not live in this repository at all.
# The canonical copy is the machine-local file named by BUGNARRATOR_SIGNING_ENV
# (default ~/.config/bug-narrator/signing.env): it is untracked, it lives
# outside the tree, and no value of it is written into any file here. So this
# check cannot read the identifiers out of the repository, and runs in two
# tiers instead.
#
# Tier 1 - exact. When the machine-local values are available, every tracked
# text file is scanned for them, whatever shape they take. This is the tier
# that catches a value copied into any tracked file, and it covers the whole
# tree: every file in this public repository is world-readable.
#
# Tier 2 - shape. Always, including on CI where the machine-local values do
# not exist: the published documentation may not carry an e-mail address at
# all. The notarization Apple ID is an e-mail address, and the original leak
# was an Apple ID in a doc, so this tier catches the same class of leak
# without needing to know the value. Reserved example domains are exempt.
#
# Tier 2 is a backstop, not a replacement. It cannot see the team ID or the
# keychain profile name: neither has a shape that can be told apart from
# ordinary text, so only tier 1 can catch those, and only on the machine that
# holds the settings. Keep both.
#
# The check fails closed on the things it can decide alone: if the tracked
# files cannot be listed, it reports the failure rather than reporting a
# clean scan it did not perform.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/signing-settings.sh
. "$ROOT/scripts/signing-settings.sh"

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

# ── The tracked files are the published surface ──────────────────────────────

TRACKED_FILES=""
if ! TRACKED_FILES="$(git ls-files)"; then
  printf 'FAIL: could not list the tracked files\n' >&2
  exit 1
fi
if [[ -z "$TRACKED_FILES" ]]; then
  printf 'FAIL: no tracked files were found to scan\n' >&2
  exit 1
fi

# ── Tier 1: the exact values, when this machine holds them ──────────────────

TEAM_ID="$(bugnarrator_signing_setting BUGNARRATOR_DEVELOPMENT_TEAM)"
NOTARY_PROFILE="$(bugnarrator_signing_setting BUGNARRATOR_NOTARY_PROFILE)"
APPLE_ID="$(bugnarrator_signing_setting BUGNARRATOR_NOTARY_APPLE_ID)"

# The password-manager item name is built from the profile name, so the
# profile value covers it.
PASSWORD_MANAGER_ITEM=""
if [[ -n "$NOTARY_PROFILE" ]]; then
  PASSWORD_MANAGER_ITEM="Apple Notarytool - ${NOTARY_PROFILE}"
fi

# Reports every line of a file that carries a literal identifier.
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

TIER1_RAN=0
if [[ -n "$TEAM_ID" || -n "$NOTARY_PROFILE" || -n "$APPLE_ID" ]]; then
  TIER1_RAN=1
  printf 'scanning the whole tracked tree for the owner identifiers on this machine\n'
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    [[ -f "$file" ]] || continue
    scan_for_literal "$file" "$TEAM_ID" "development team ID"
    scan_for_literal "$file" "$NOTARY_PROFILE" "notary keychain profile name"
    scan_for_literal "$file" "$PASSWORD_MANAGER_ITEM" "password-manager item name"
    scan_for_literal "$file" "$APPLE_ID" "notarization Apple ID"
  done <<<"$TRACKED_FILES"
else
  printf 'note: no machine-local signing settings found (%s); the exact scan is skipped on this machine\n' "$BUGNARRATOR_SIGNING_ENV"
fi

# ── Tier 2: the published documentation may not carry an e-mail address ─────

EMAIL_RE='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'

# The documentation a reader sees. The docs site mirrors these files, so a
# leak here is a leak on the published site too.
PUBLISHED_DOCS=()
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  PUBLISHED_DOCS+=("$file")
done < <(
  for f in README.md CHANGELOG.md CHANGELOG-archive.md; do
    [[ -f "$f" ]] && printf '%s\n' "$f"
  done
  git ls-files -- 'docs/*.md' 'docs/**/*.md' 'site/*.md' 'site/**/*.md'
)

if [[ "${#PUBLISHED_DOCS[@]}" -eq 0 ]]; then
  printf 'FAIL: no published documentation was found to scan\n' >&2
  exit 1
fi

# Reserved example domains carry no identity: they are the RFC 2606 and
# RFC 6762 names, plus the addresses GitHub issues for commits.
email_is_reserved() {
  local domain="$1"
  domain="${domain,,}"
  case "$domain" in
    example.com|example.org|example.net|example.edu) return 0 ;;
    *.example.com|*.example.org|*.example.net|*.example.edu) return 0 ;;
    localhost|*.localhost|*.local|*.invalid|*.test) return 0 ;;
    *.noreply.github.com) return 0 ;;
  esac
  return 1
}

for file in "${PUBLISHED_DOCS[@]}"; do
  [[ -f "$file" ]] || continue
  while IFS= read -r hit; do
    [[ -n "$hit" ]] || continue
    hit_line="${hit%%:*}"
    address="${hit#*:}"
    email_is_reserved "${address#*@}" && continue
    report_hit "$file" "$hit_line" "an e-mail address"
  done < <(grep -nIoE "$EMAIL_RE" "$file" 2>/dev/null || true)
done

# ── A published command must carry a placeholder, never a live value ───────

# A published command is one a reader copies from. A source file is allowed
# to hold its own defaults, so this rule is scoped to the markdown the
# repository publishes.
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

if [[ "$TIER1_RAN" -eq 1 ]]; then
  printf 'PASS: the published surface carries no owner notarization identifiers\n'
else
  printf 'PASS: the published documentation carries no owner notarization identifiers (the exact scan needs this machine\x27s signing settings)\n'
fi
