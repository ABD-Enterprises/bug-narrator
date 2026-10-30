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
# make both assertions above vacuously true. The phrase below is the gate's
# own wording; the helper's message is different, so this cannot be satisfied
# by the helper's stderr alone.
if ! grep -q 'refusing to report a clean scan' "$gate_output"; then
  printf 'FAIL: validate.sh failed for an unrelated reason, not the diff check\n' >&2
  exit 1
fi

# CI checks out a shallow clone, where the merge base can be unreachable. The
# helper has to produce the change set there too, and it must not report
# "nothing changed" when it could not establish one. This replays that
# checkout shape in a throwaway repository.
check_shallow_checkout() {
  local workspace base_sha merge_sha identical_sha
  workspace="$(mktemp -d)"
  trap 'rm -rf "$workspace"' RETURN

  git init -q -b main "$workspace/origin"
  git -C "$workspace/origin" config user.email check@example.invalid
  git -C "$workspace/origin" config user.name "Changed Files Check"
  printf 'one\n' >"$workspace/origin/base.txt"
  git -C "$workspace/origin" add -A
  git -C "$workspace/origin" commit -qm "base"
  base_sha="$(git -C "$workspace/origin" rev-parse HEAD)"
  printf 'two\n' >"$workspace/origin/moved-on.txt"
  git -C "$workspace/origin" add -A
  git -C "$workspace/origin" commit -qm "the base branch moved on"
  git -C "$workspace/origin" checkout -q -b feature
  printf 'three\n' >"$workspace/origin/feature.txt"
  git -C "$workspace/origin" add -A
  git -C "$workspace/origin" commit -qm "the branch's own change"
  git -C "$workspace/origin" checkout -q main
  git -C "$workspace/origin" merge -q --no-ff feature -m "merge the branch"
  merge_sha="$(git -C "$workspace/origin" rev-parse HEAD)"
  # A second commit with the same tree as the merge: the base ref resolves, but
  # the trees match, so the change set cannot be established.
  git -C "$workspace/origin" checkout -q -b identical
  git -C "$workspace/origin" commit -q --allow-empty -m "the same tree"
  identical_sha="$(git -C "$workspace/origin" rev-parse HEAD)"

  git init -q "$workspace/shallow"
  git -C "$workspace/shallow" remote add origin "file://$workspace/origin"
  git -C "$workspace/shallow" fetch -q --no-tags --depth=2 origin "$merge_sha"
  git -C "$workspace/shallow" checkout -q FETCH_HEAD
  git -C "$workspace/shallow" fetch -q --no-tags --depth=1 origin "$base_sha"
  git -C "$workspace/shallow" fetch -q --no-tags --depth=1 origin "$identical_sha"
  mkdir -p "$workspace/shallow/scripts"
  cp "$HELPER" "$workspace/shallow/scripts/changed-files.sh"

  # The merge base is unreachable in this checkout, so the helper has to fall
  # back to comparing the trees and still report the branch's own file.
  local listed
  if ! listed="$("$workspace/shallow/scripts/changed-files.sh" "$base_sha" 2>/dev/null)"; then
    printf 'FAIL: changed-files.sh failed in a shallow checkout where the merge base is unreachable\n' >&2
    return 1
  fi
  if [[ "$listed" != *"feature.txt"* ]]; then
    printf 'FAIL: changed-files.sh did not report the branch change in a shallow checkout\n' >&2
    return 1
  fi

  # An empty result from the fallback means the change set is unknown, not that
  # nothing changed. It has to be an error, not a clean scan.
  if "$workspace/shallow/scripts/changed-files.sh" "$identical_sha" >/dev/null 2>&1; then
    printf 'FAIL: changed-files.sh reported no changes in a shallow checkout where the change set is unknown\n' >&2
    return 1
  fi
}

if ! check_shallow_checkout; then
  exit 1
fi

printf 'PASS: validate.sh fails closed on an unresolvable base ref and succeeds on a resolvable one\n'
