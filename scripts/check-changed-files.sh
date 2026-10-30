#!/usr/bin/env bash
# Verify that the validation gate fails closed when it cannot diff against the
# base ref.
#
# validate.sh used to build its scan list inside a process substitution, where
# git's exit status was discarded. A stale, missing or unrelated base ref
# therefore produced an empty list, and validate.sh reported a green "no
# scannable changed files" PASS while the scanner had looked at nothing. The
# helper scripts/changed-files.sh keeps the diff's exit status, and this check
# pins the behaviour the gate depends on — including the gate itself, not just
# the helper.
#
# Exits 0 with a one-line PASS message when the gate holds; exits 1 with the
# reason otherwise.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

HELPER="$ROOT/scripts/changed-files.sh"
GATE="$ROOT/scripts/validate.sh"

if [[ ! -x "$HELPER" ]]; then
  printf 'FAIL: %s is missing or not executable\n' "$HELPER" >&2
  exit 1
fi

# The helper must fail on a base ref that does not exist, and must not print a
# file list.
if output="$("$HELPER" "bogus-nonexistent-ref" 2>/dev/null)"; then
  printf 'FAIL: changed-files.sh accepted a base ref that does not exist\n' >&2
  exit 1
fi
if [[ -n "$output" ]]; then
  printf 'FAIL: changed-files.sh printed files for a base ref that does not exist\n' >&2
  exit 1
fi

# A base ref that does exist must succeed. HEAD against HEAD is the "nothing
# changed" case: an empty list with exit 0, not a failure.
if ! "$HELPER" HEAD >/dev/null; then
  printf 'FAIL: changed-files.sh failed on a base ref that exists\n' >&2
  exit 1
fi

# The gate itself must fail on the same base ref, and must not report a clean
# scan. The gate stops at the diff step, before any scanner runs, so this is
# cheap. VALIDATE_SKIP_CHANGED_FILES_SELF_CHECK stops the gate from calling
# this check again, so it cannot recurse.
gate_output="$(mktemp)"
trap 'rm -f "$gate_output"' EXIT

# AI_VALIDATOR_BASE_REF takes precedence over the argument in validate.sh, so
# it has to be cleared for the bogus ref to be the one the gate sees.
if env -u AI_VALIDATOR_BASE_REF VALIDATE_SKIP_CHANGED_FILES_SELF_CHECK=1 \
  "$GATE" "bogus-nonexistent-ref" >"$gate_output" 2>&1; then
  printf 'FAIL: validate.sh accepted a base ref that does not exist\n' >&2
  exit 1
fi
if grep -q 'no scannable changed files' "$gate_output"; then
  printf 'FAIL: validate.sh reported a clean scan for a base ref that does not exist\n' >&2
  exit 1
fi
# The gate has to have failed for the right reason: an earlier failure would
# make both assertions above vacuously true.
if ! grep -q 'could not diff against' "$gate_output"; then
  printf 'FAIL: validate.sh failed for an unrelated reason, not the diff check\n' >&2
  exit 1
fi

printf 'PASS: validate.sh fails closed on an unresolvable base ref and succeeds on a resolvable one\n'
