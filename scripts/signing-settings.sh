#!/usr/bin/env bash
# Reads the owner's signing and notarization settings from the machine-local
# source of truth.
#
# This repository is public, so no value of the owner's lives in it: not in a
# script, not in a doc, not in a source file. The canonical copy is the file
# named by BUGNARRATOR_SIGNING_ENV (default
# ~/.config/bug-narrator/signing.env), which lives outside this repository
# and is never tracked. The environment overrides the file, so a CI job or a
# one-off invocation can supply a value without writing one to disk.
#
# The file holds one setting per line, with these names:
#
#   BUGNARRATOR_DEVELOPMENT_TEAM   the Developer ID team that signs releases
#   BUGNARRATOR_NOTARY_PROFILE      the notarytool keychain profile name
#   BUGNARRATOR_NOTARY_APPLE_ID     the Apple account that owns the profile
#
# Accepted line forms (blank lines and lines starting with "#" are ignored;
# the first matching line wins):
#
#   BUGNARRATOR_DEVELOPMENT_TEAM="ABCDE12345"
#   BUGNARRATOR_DEVELOPMENT_TEAM=ABCDE12345
#   export BUGNARRATOR_DEVELOPMENT_TEAM="ABCDE12345"
#   BUGNARRATOR_DEVELOPMENT_TEAM = "ABCDE12345"
#
# A value is taken literally: nothing in it is expanded or interpolated. A
# value may contain spaces.
#
# scripts/build_dmg.sh, local-transcription/build_standalone.sh and
# scripts/check-doc-identifiers.sh all source this file, so the three read
# one place and cannot drift into holding separate copies.

BUGNARRATOR_SIGNING_ENV="${BUGNARRATOR_SIGNING_ENV:-$HOME/.config/bug-narrator/signing.env}"

# Prints the value one setting has in the machine-local file. An unset
# setting prints nothing.
bugnarrator_signing_file_value() {
  local name="$1"
  local file="$2"

  [[ -f "$file" ]] || return 0

  tr -d '\r' <"$file" | awk -v name="$name" '
    {
      line = $0

      # Blank lines and comments carry no setting.
      if (line ~ /^[[:space:]]*#/) next
      if (line ~ /^[[:space:]]*$/) next

      # An "export " prefix is allowed.
      sub(/^[[:space:]]*export[[:space:]]+/, "", line)

      eq = index(line, "=")
      if (eq == 0) next

      key = substr(line, 1, eq - 1)
      value = substr(line, eq + 1)

      gsub(/^[[:space:]]+/, "", key)
      gsub(/[[:space:]]+$/, "", key)
      gsub(/^[[:space:]]+/, "", value)
      gsub(/[[:space:]]+$/, "", value)

      if (key != name) next

      quote = sprintf("%c", 39)
      if (value ~ /^".*"$/) {
        value = substr(value, 2, length(value) - 2)
      } else if (value ~ ("^" quote ".*" quote "$")) {
        value = substr(value, 2, length(value) - 2)
      } else {
        # An unquoted value may be followed by a comment.
        hash = index(value, " #")
        if (hash > 0) value = substr(value, 1, hash - 1)
        gsub(/[[:space:]]+$/, "", value)
      }

      print value
      exit
    }
  '
}

# Prints the effective value of one setting: the environment first, then the
# machine-local file. An unset setting prints nothing.
bugnarrator_signing_setting() {
  local name="$1"
  local value=""

  value="$(printenv "$name" 2>/dev/null || true)"
  if [[ -z "$value" ]]; then
    value="$(bugnarrator_signing_file_value "$name" "$BUGNARRATOR_SIGNING_ENV")"
  fi

  printf '%s' "$value"
  return 0
}

# Prints every candidate value of one setting, one per line: the environment
# value and the file value. The audit needs both, because the environment
# overrides the file at build time while the file's own value is still a
# value that must not be published.
bugnarrator_signing_setting_candidates() {
  local name="$1"
  local value=""

  value="$(printenv "$name" 2>/dev/null || true)"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  fi

  value="$(bugnarrator_signing_file_value "$name" "$BUGNARRATOR_SIGNING_ENV")"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
  fi

  return 0
}
