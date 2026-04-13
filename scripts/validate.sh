#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BASE_REF="${AI_VALIDATOR_BASE_REF:-${1:-}}"
VALIDATION_ARTIFACT_DIR="artifacts/validation"
SEMGREP_STATUS_FILE="${VALIDATION_ARTIFACT_DIR}/semgrep-status.txt"
SEMGREP_OUTPUT_FILE="${VALIDATION_ARTIFACT_DIR}/semgrep-output.txt"

mkdir -p "$VALIDATION_ARTIFACT_DIR"
rm -f "$SEMGREP_STATUS_FILE" "$SEMGREP_OUTPUT_FILE"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  if docker run --rm -v "${ROOT}":/src -w /src -e SEMGREP_APP_TOKEN semgrep/semgrep semgrep --config=auto --error . >"$SEMGREP_OUTPUT_FILE" 2>&1; then
    printf 'PASS: semgrep completed successfully
' >"$SEMGREP_STATUS_FILE"
  else
    cat "$SEMGREP_OUTPUT_FILE" >&2
    exit 1
  fi
else
  printf 'NOT RUN: Docker is unavailable in this environment
' >"$SEMGREP_STATUS_FILE"
fi

if [[ -n "$BASE_REF" ]]; then
  node tools/validators/enforce-runtime-guardrails.mjs --repo . --config ai.config.json --base "$BASE_REF"
else
  node tools/validators/enforce-runtime-guardrails.mjs --repo . --config ai.config.json
fi
