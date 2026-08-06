#!/usr/bin/env bash
# Merge-queue verification entry point (#920).
#
# `.github/workflows/orc-merge-queue.yml` runs this file "if present". It was
# never present, so the "ORC Merge Queue / call" check printed a placeholder
# message and passed unconditionally — a gate that validated nothing.
#
# This chains the checks the repo already trusts rather than inventing new
# ones, so the merge-queue result means the same thing as local validation:
#
#   scripts/validate.sh          semgrep (changed files) + swift parse +
#                                effort-leak audit + docs audit
#   scripts/swift-parse-check.sh explicit parse sweep, in case validate.sh
#                                skipped it for lack of a toolchain
#
# It deliberately does NOT run xcodebuild. The heavy build/test lives in
# `macos-build-and-test` in ci.yml, which now also triggers on `merge_group`,
# so duplicating it here would double the most expensive job in the pipeline.
#
# Exit non-zero on the first failing check.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BASE_REF="${1:-${AI_VALIDATOR_BASE_REF:-}}"
if [[ -z "$BASE_REF" && -n "${GITHUB_BASE_REF:-}" ]]; then
  BASE_REF="origin/${GITHUB_BASE_REF}"
fi
if [[ -z "$BASE_REF" ]] && git rev-parse --verify origin/main >/dev/null 2>&1; then
  BASE_REF="origin/main"
fi

echo "verify: base ref = ${BASE_REF:-<none>}"

echo "verify: running scripts/validate.sh"
bash "$ROOT/scripts/validate.sh" ${BASE_REF:+"$BASE_REF"}

echo "verify: running scripts/swift-parse-check.sh"
bash "$ROOT/scripts/swift-parse-check.sh"

echo "verify: PASS"
