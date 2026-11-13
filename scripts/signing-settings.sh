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
# The file holds one NAME="value" pair per line, with these names:
#
#   BUGNARRATOR_DEVELOPMENT_TEAM   the Developer ID team that signs releases
#   BUGNARRATOR_NOTARY_PROFILE      the notarytool keychain profile name
#   BUGNARRATOR_NOTARY_APPLE_ID     the Apple account that owns the profile
#
# scripts/build_dmg.sh, local-transcription/build_standalone.sh and
# scripts/check-doc-identifiers.sh all source this file, so the three read
# one place and cannot drift into holding separate copies.

BUGNARRATOR_SIGNING_ENV="${BUGNARRATOR_SIGNING_ENV:-$HOME/.config/bug-narrator/signing.env}"

# Prints the value of one setting: the machine-local file first, then the
# environment of the same name. An unset setting prints nothing.
bugnarrator_signing_setting() {
  local name="$1"
  local value=""

  if [[ -f "$BUGNARRATOR_SIGNING_ENV" ]]; then
    value="$(sed -n "s/^${name}=\"\(.*\)\"$/\1/p" "$BUGNARRATOR_SIGNING_ENV" | head -1)"
  fi

  if [[ -z "$value" ]]; then
    value="$(printenv "$name" 2>/dev/null || true)"
  fi

  printf '%s' "$value"
}
