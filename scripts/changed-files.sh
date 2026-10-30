#!/usr/bin/env bash
# Print the repository files that differ between a base ref and HEAD, one path
# per line.
#
# The diff runs as a plain command, not inside a process substitution, so git's
# exit status survives: a base ref that cannot be resolved is an error instead
# of an empty list. An empty list with exit 0 means "nothing changed", which is
# a genuine answer and not a failure.
#
# The three-dot form (the change set of a branch, measured from its merge base)
# is preferred because it is exactly what a branch changed. A shallow checkout
# may not contain the merge base, in which case the two-dot form (a direct tree
# comparison, which needs no merge base) is used instead. Both forms fail when
# the base ref cannot be resolved at all, so the caller can still fail closed.
#
# Usage: scripts/changed-files.sh <base-ref>

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BASE_REF="${1:-}"
if [[ -z "$BASE_REF" ]]; then
  exit 0
fi

# core.quotePath=false keeps non-ASCII paths printable. With the default
# quoting, a file whose name contains one is emitted as an escaped, quoted
# string that no longer names a file on disk, and it would be skipped.
error_file="$(mktemp)"
trap 'rm -f "$error_file"' EXIT

if files="$(git -c core.quotePath=false diff --name-only "${BASE_REF}...HEAD" -- 2>"$error_file")"; then
  if [[ -n "$files" ]]; then
    printf '%s\n' "$files"
  fi
  exit 0
fi

merge_base_error="$(cat "$error_file")"

if files="$(git -c core.quotePath=false diff --name-only "${BASE_REF}" HEAD -- 2>"$error_file")"; then
  # The merge base is not reachable: a shallow checkout, or a base ref that has
  # moved on since the event was recorded. Comparing the two trees directly is
  # the best available answer; it lists the same files plus any change the base
  # branch took after the branch point.
  printf 'note: the merge base for %s is not available (%s); comparing trees directly.\n' \
    "$BASE_REF" "$merge_base_error" >&2
  if [[ -n "$files" ]]; then
    printf '%s\n' "$files"
  fi
  exit 0
fi

printf 'error: could not diff against %s: %s\n' "$BASE_REF" "$(cat "$error_file")" >&2
exit 1
