#!/usr/bin/env bash
# Local + CI guardrails entry point.
#
# Runs semgrep against the changed files (Docker first, then a locally
# installed `semgrep` on PATH — pip / pipx / Homebrew — as a fallback so cloud
# / phone development sessions without Docker still produce a non-trivial
# signal). Then runs swift-parse-check.sh which is cheap and portable across
# macOS Xcode, Linux swift.org toolchains, and cloud sandboxes.
#
# Status outputs land under artifacts/validation/ so the source of each
# check is visible in CI artifacts:
#   semgrep-status.txt      PASS / NOT RUN with the runner that produced it
#   swift-parse-status.txt  PASS / NOT RUN from swift-parse-check.sh

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
LOCAL_TRANSCRIPTION_STATUS_FILE="${VALIDATION_ARTIFACT_DIR}/local-transcription-status.txt"
LOCAL_TRANSCRIPTION_OUTPUT_FILE="${VALIDATION_ARTIFACT_DIR}/local-transcription-output.txt"
EFFORT_LEAK_STATUS_FILE="${VALIDATION_ARTIFACT_DIR}/effort-leak-status.txt"
EFFORT_LEAK_OUTPUT_FILE="${VALIDATION_ARTIFACT_DIR}/effort-leak-output.txt"
mkdir -p "$VALIDATION_ARTIFACT_DIR"
rm -f \
  "$SEMGREP_STATUS_FILE" \
  "$SEMGREP_OUTPUT_FILE" \
  "$LOCAL_TRANSCRIPTION_STATUS_FILE" \
  "$LOCAL_TRANSCRIPTION_OUTPUT_FILE" \
  "$EFFORT_LEAK_STATUS_FILE" \
  "$EFFORT_LEAK_OUTPUT_FILE"

should_skip_semgrep_target() {
  local target="$1"

  case "$target" in
    tools/validators/*)
      return 0
      ;;
  esac

  return 1
}

# Build the changed-files target list, or fall back to scanning the whole
# tree when there is no base ref available (e.g. first push of a branch).
SEMGREP_TARGETS=()
if [[ -n "$BASE_REF" ]]; then
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    [[ -f "$target" ]] || continue
    should_skip_semgrep_target "$target" && continue
    SEMGREP_TARGETS+=("$target")
  done < <(git diff --name-only "${BASE_REF}...HEAD" --)
fi

# Returns 0 on semgrep pass, 1 on semgrep findings, 2 on "runner unavailable".
run_semgrep_docker() {
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    return 2
  fi

  if docker run --rm -v "${ROOT}":/src -w /src -e SEMGREP_APP_TOKEN \
    semgrep/semgrep semgrep scan --config=auto --error "$@" \
    >"$SEMGREP_OUTPUT_FILE" 2>&1; then
    return 0
  fi
  return 1
}

run_semgrep_local() {
  if ! command -v semgrep >/dev/null 2>&1; then
    return 2
  fi

  if semgrep scan --config=auto --error "$@" >"$SEMGREP_OUTPUT_FILE" 2>&1; then
    return 0
  fi
  return 1
}

if [[ ${#SEMGREP_TARGETS[@]} -eq 0 && -n "$BASE_REF" ]]; then
  printf 'PASS: no scannable changed files for semgrep\n' >"$SEMGREP_STATUS_FILE"
else
  if [[ ${#SEMGREP_TARGETS[@]} -eq 0 ]]; then
    SEMGREP_TARGETS=(.)
  fi

  semgrep_outcome="unknown"
  set +e
  run_semgrep_docker "${SEMGREP_TARGETS[@]}"
  docker_status=$?
  set -e

  case "$docker_status" in
    0)
      printf 'PASS: semgrep completed successfully via docker\n' >"$SEMGREP_STATUS_FILE"
      semgrep_outcome="pass"
      ;;
    1)
      cat "$SEMGREP_OUTPUT_FILE" >&2
      exit 1
      ;;
    *)
      set +e
      run_semgrep_local "${SEMGREP_TARGETS[@]}"
      local_status=$?
      set -e

      case "$local_status" in
        0)
          printf 'PASS: semgrep completed successfully via local PATH\n' >"$SEMGREP_STATUS_FILE"
          semgrep_outcome="pass"
          ;;
        1)
          cat "$SEMGREP_OUTPUT_FILE" >&2
          exit 1
          ;;
        *)
          printf 'NOT RUN: neither docker nor a local semgrep on PATH is available\n' >"$SEMGREP_STATUS_FILE"
          semgrep_outcome="skipped"
          ;;
      esac
      ;;
  esac
  : "$semgrep_outcome"
fi

# Always run the cloud-portable Swift parse check. It self-skips with a clean
# exit when no Swift toolchain is available, and fails the build only on
# syntax errors — never on missing toolchains or missing imports.
"${ROOT}/scripts/swift-parse-check.sh"

if [[ -x "$ROOT/scripts/effort-leak-audit.sh" ]]; then
  if "$ROOT/scripts/effort-leak-audit.sh" >"$EFFORT_LEAK_OUTPUT_FILE" 2>&1; then
    if grep -q '^PASS:' "$EFFORT_LEAK_OUTPUT_FILE"; then
      printf 'PASS: effort-leak audit found no duplicate, blocked-active, or unlinkable PR state\n' \
        >"$EFFORT_LEAK_STATUS_FILE"
    else
      printf 'NOT RUN: effort-leak audit skipped because GitHub CLI/auth was unavailable\n' \
        >"$EFFORT_LEAK_STATUS_FILE"
    fi
  else
    cat "$EFFORT_LEAK_OUTPUT_FILE" >&2
    exit 1
  fi
fi

if [[ -f "$ROOT/local-transcription/server.py" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 -m py_compile \
      "$ROOT/local-transcription/server.py" \
      "$ROOT/local-transcription/test_server.py" \
      >"$LOCAL_TRANSCRIPTION_OUTPUT_FILE" 2>&1
  else
    printf 'NOT RUN: python3 is not available for local transcription syntax checks\n' \
      >"$LOCAL_TRANSCRIPTION_STATUS_FILE"
    exit 0
  fi

  local_transcription_python="$ROOT/local-transcription/venv/bin/python"
  if [[ -x "$local_transcription_python" ]]; then
    if "$local_transcription_python" -m unittest discover \
      -s "$ROOT/local-transcription" \
      -p 'test_*.py' \
      >>"$LOCAL_TRANSCRIPTION_OUTPUT_FILE" 2>&1; then
      printf 'PASS: local transcription server syntax and unit checks passed\n' \
        >"$LOCAL_TRANSCRIPTION_STATUS_FILE"
    else
      cat "$LOCAL_TRANSCRIPTION_OUTPUT_FILE" >&2
      exit 1
    fi
  else
    printf 'PASS: local transcription server syntax checks passed; unit checks not run because local-transcription/venv is missing\n' \
      >"$LOCAL_TRANSCRIPTION_STATUS_FILE"
  fi
fi
