#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BASE_REF="${AI_VALIDATOR_BASE_REF:-${1:-}}"

if [[ -n "$BASE_REF" ]]; then
  node tools/validators/enforce-runtime-guardrails.js --repo . --config ai.config.json --base "$BASE_REF"
else
  node tools/validators/enforce-runtime-guardrails.js --repo . --config ai.config.json
fi
