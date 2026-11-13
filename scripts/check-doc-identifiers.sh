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
# file is scanned for them, whatever shape they take. This is the tier
# that catches a value copied into any tracked file, and it covers the whole
# tree: every file in this public repository is world-readable. Both the
# environment value and the file value are scanned, because the environment
# overrides the file at build time while the file's own value is still a
# value that must not be published.
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
# clean scan it did not perform, and a settings file it cannot read is an
# error rather than an absent configuration.

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

# Every value to look for, with what to call it when it is found.
NEEDLES=()
DESCRIPTIONS=()

add_needle() {
  local needle="$1"
  local description="$2"
  [[ -n "$needle" ]] || return 0
  NEEDLES+=("$needle")
  DESCRIPTIONS+=("$description")
  return 0
}

while IFS= read -r value; do
  add_needle "$value" "development team ID"
done < <(bugnarrator_signing_setting_candidates BUGNARRATOR_DEVELOPMENT_TEAM)

while IFS= read -r value; do
  add_needle "$value" "notary keychain profile name"
  # The password-manager item name is built from the profile name, so the
  # profile value covers it.
  add_needle "Apple Notarytool - ${value}" "password-manager item name"
done < <(bugnarrator_signing_setting_candidates BUGNARRATOR_NOTARY_PROFILE)

while IFS= read -r value; do
  add_needle "$value" "notarization Apple ID"
done < <(bugnarrator_signing_setting_candidates BUGNARRATOR_NOTARY_APPLE_ID)

# The build scripts also honour the older variable names, so a value supplied
# through one of those is signed and injected like any other. It has to be
# scanned like any other too.
while IFS= read -r value; do
  add_needle "$value" "development team ID"
done < <(printenv DEVELOPMENT_TEAM 2>/dev/null || true)

while IFS= read -r value; do
  add_needle "$value" "development team ID"
done < <(printenv EXPECTED_SIGNING_TEAM 2>/dev/null || true)

while IFS= read -r value; do
  add_needle "$value" "notary keychain profile name"
  add_needle "Apple Notarytool - ${value}" "password-manager item name"
done < <(printenv NOTARY_PROFILE 2>/dev/null || true)

# Reports every line of the tracked tree that carries a literal identifier.
#
# The match is case-insensitive. The Apple ID is a mailbox, and a mailbox is
# reachable at any case, so a differently-cased spelling of it is the same
# account and a case-sensitive check would wave it through. The team ID and
# the profile name are case-insensitive for the same reason: a copy of the
# value that has been retyped in a different case is still the value.
#
# The scan is one git grep over the tracked tree rather than a grep per file
# per value: this check runs on every push, and the per-file form took about
# a minute on this tree.
scan_tree_for_literal() {
  local needle="$1"
  local description="$2"

  local output
  output="$(git grep -n -i -F -e "$needle" 2>/dev/null || true)"

  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    case "$line" in
      "Binary file "*)
        # A binary file that matches has no useful line number, but it is
        # still a published copy and must not be reported as clean.
        local binary_path="${line#Binary file }"
        report_hit "${binary_path% matches}" "" "$description"
        ;;
      *)
        report_hit "${line%%:*}" "$(printf '%s' "$line" | cut -d: -f2)" "$description"
        ;;
    esac
  done <<<"$output"
}

TIER1_RAN=0
if [[ "${#NEEDLES[@]}" -gt 0 ]]; then
  TIER1_RAN=1
  printf 'scanning the whole tracked tree for the owner identifiers on this machine\n'
  for index in "${!NEEDLES[@]}"; do
    scan_tree_for_literal "${NEEDLES[$index]}" "${DESCRIPTIONS[$index]}"
  done
elif [[ -f "$BUGNARRATOR_SIGNING_ENV" ]]; then
  # The file is there but nothing could be read out of it. That is a
  # misconfigured file, not an absent one, and it must not be reported as a
  # clean scan that was never performed: a typo in a key name would
  # otherwise switch the exact tier off without a word.
  printf 'FAIL: %s exists, but none of BUGNARRATOR_DEVELOPMENT_TEAM, BUGNARRATOR_NOTARY_PROFILE and BUGNARRATOR_NOTARY_APPLE_ID could be read from it.\n' "$BUGNARRATOR_SIGNING_ENV" >&2
  printf 'hint: the file holds one NAME="value" per line, for example BUGNARRATOR_DEVELOPMENT_TEAM="...".\n' >&2
  exit 1
else
  printf 'note: no machine-local signing settings found (%s); the exact scan is skipped on this machine\n' "$BUGNARRATOR_SIGNING_ENV"
fi

# ── Tier 2: the published documentation may not carry an e-mail address ─────

EMAIL_RE='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'

# The published surface: every tracked markdown file, plus everything under
# .github, docs and site whatever its format.
#
# The published surface is wider than docs/: SECURITY.md, CONTRIBUTING.md,
# QUICKSTART.md, the Windows readme, the issue templates and the workflow
# files are published too, and the original leak was an Apple ID in a
# published document. Scoping the scan to a curated list would let any file
# outside that list carry the identifier while CI stayed green.
#
# The wider tree is out of scope for this shape check, and the reason is
# concrete: a tracked test fixture carries a genuine corporate e-mail
# address, and the asset catalogs and data files carry byte sequences that
# read like an address without being one. Both would have to be published
# here to be allow-listed, so the shape check stays on the surface a reader
# actually sees. Tier 1 covers the whole tree on the machine that holds the
# settings.
PUBLISHED_DOCS=()
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  PUBLISHED_DOCS+=("$file")
done < <(
  {
    git ls-files -- '*.md'
    git ls-files -- .github docs site
  } | sort -u
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

  # A flag written as FLAG=value carries its value after the "=".
  value="${value#=}"

  # Strip surrounding quotes so a quoted expansion is recognised.
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"

  # An explicitly empty value carries nothing to publish.
  if [[ -z "$value" ]]; then
    return 0
  fi

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

    # A flag written as FLAG=value carries its value after the "=".
    value="${value#=}"

    # The next option on the line is not this flag's value.
    if [[ "$value" == -* ]]; then
      continue
    fi

    printf '%s\t%s\n' "$lineno" "$value"
  done < <(grep -nIF -- "$flag" "$file" 2>/dev/null || true)
}

# The published surface, the same one tier 2 scans: a command a reader can
# copy out of a workflow file or a doc is as copyable as one in a markdown
# page. The list is read line by line, because it is a newline-separated
# string and iterating it as an array would expand the whole listing into
# one word.
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  [[ -f "$file" ]] || continue

  for flag in "--apple-id" "--team-id" "store-credentials"; do
    while IFS=$'\t' read -r lineno value; do
      [[ -n "$value" ]] || continue
      if ! is_placeholder "$value"; then
        report_hit "$file" "$lineno" "a literal value after '$flag'"
      fi
    done < <(flag_values "$file" "$flag")
  done

  # The YAML form of the same setting is as copy-pasteable as the shell one.
  for assignment in "DEVELOPMENT_TEAM=" "DEVELOPMENT_TEAM:" "NOTARY_PROFILE=" "NOTARY_PROFILE:"; do
    while IFS=$'\t' read -r lineno value; do
      [[ -n "$value" ]] || continue
      if ! is_placeholder "$value"; then
        report_hit "$file" "$lineno" "a literal value after '$assignment'"
      fi
    done < <(flag_values "$file" "$assignment")
  done
done <<<"$(printf '%s\n' "${PUBLISHED_DOCS[@]}")"

if [[ "$FAILURES" -ne 0 ]]; then
  printf '\nDocumentation identifier audit failed.\n' >&2
  exit 1
fi

if [[ "$TIER1_RAN" -eq 1 ]]; then
  printf 'PASS: the published surface carries no owner notarization identifiers\n'
else
  printf 'PASS: the published documentation carries no owner notarization identifiers (the exact scan needs this machine\x27s signing settings)\n'
fi
