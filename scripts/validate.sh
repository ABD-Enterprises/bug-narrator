#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BASE_REF="${AI_VALIDATOR_BASE_REF:-${1:-}}"
if [[ -z "$BASE_REF" && -n "${GITHUB_BASE_REF:-}" ]]; then
  BASE_REF="origin/${GITHUB_BASE_REF}"
fi
if [[ -z "$BASE_REF" ]] && git rev-parse --verify origin/main >/dev/null 2>&1; then
  BASE_REF="origin/main"
fi

VALIDATION_ARTIFACT_DIR="artifacts/validation"
SEMGREP_STATUS_FILE="${VALIDATION_ARTIFACT_DIR}/semgrep-status.txt"
SEMGREP_OUTPUT_FILE="${VALIDATION_ARTIFACT_DIR}/semgrep-output.txt"
mkdir -p "$VALIDATION_ARTIFACT_DIR"
rm -f "$SEMGREP_STATUS_FILE" "$SEMGREP_OUTPUT_FILE"

should_skip_semgrep_target() {
  local target="$1"

  case "$target" in
    tools/validators/*)
      return 0
      ;;
  esac

  return 1
}

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  SEMGREP_TARGETS=()

  if [[ -n "$BASE_REF" ]]; then
    while IFS= read -r target; do
      [[ -n "$target" ]] || continue
      [[ -f "$target" ]] || continue
      should_skip_semgrep_target "$target" && continue
      SEMGREP_TARGETS+=("$target")
    done < <(git diff --name-only "${BASE_REF}...HEAD" --)
  fi

  if [[ ${#SEMGREP_TARGETS[@]} -eq 0 ]]; then
    if [[ -n "$BASE_REF" ]]; then
      printf 'PASS: no scannable changed files for semgrep\n' >"$SEMGREP_STATUS_FILE"
    else
      SEMGREP_TARGETS=(.)
    fi
  fi

  if [[ ${#SEMGREP_TARGETS[@]} -gt 0 ]]; then
    if docker run --rm -v "${ROOT}":/src -w /src -e SEMGREP_APP_TOKEN semgrep/semgrep semgrep scan --config=auto --error "${SEMGREP_TARGETS[@]}" >"$SEMGREP_OUTPUT_FILE" 2>&1; then
      printf 'PASS: semgrep completed successfully\n' >"$SEMGREP_STATUS_FILE"
    else
      cat "$SEMGREP_OUTPUT_FILE" >&2
      exit 1
    fi
  fi
else
  printf 'NOT RUN: Docker is unavailable in this environment\n' >"$SEMGREP_STATUS_FILE"
fi

node tools/validators/enforce-versioning-standard.mjs --repo .
