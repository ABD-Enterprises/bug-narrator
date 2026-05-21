#!/usr/bin/env bash
# Swift parse-only syntax check for the BugNarrator source tree.
#
# Runs `swiftc -parse` on every Sources/**/*.swift file. The `-parse` action
# only performs lexing + parsing — no type checking, no import resolution — so
# this catches Swift syntax errors in any environment that has a Swift
# toolchain (macOS Xcode, Linux swift.org toolchain, cloud sandbox), without
# needing the macOS-only Foundation/AppKit modules that BugNarrator imports
# in semantic-checked builds.
#
# Designed for use from validate.sh and from cloud development sessions
# (Claude Code on the web/phone) where xcodebuild is unavailable.
#
# Exit codes:
#   0 on success or when swift is unavailable (clean skip)
#   non-zero if swiftc -parse reports a syntax error
#
# Status is written to artifacts/validation/swift-parse-status.txt so the
# outcome is visible in CI artifacts.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VALIDATION_ARTIFACT_DIR="artifacts/validation"
STATUS_FILE="${VALIDATION_ARTIFACT_DIR}/swift-parse-status.txt"
OUTPUT_FILE="${VALIDATION_ARTIFACT_DIR}/swift-parse-output.txt"
mkdir -p "$VALIDATION_ARTIFACT_DIR"
rm -f "$STATUS_FILE" "$OUTPUT_FILE"

SWIFT_BIN=""
if command -v swiftc >/dev/null 2>&1; then
  SWIFT_BIN="swiftc"
elif command -v swift >/dev/null 2>&1; then
  SWIFT_BIN="swift"
fi

if [[ -z "$SWIFT_BIN" ]]; then
  printf 'NOT RUN: swift toolchain unavailable in this environment\n' >"$STATUS_FILE"
  exit 0
fi

if [[ ! -d "Sources" ]]; then
  printf 'NOT RUN: Sources directory not found\n' >"$STATUS_FILE"
  exit 0
fi

# Collect every Swift source file under Sources/.
SWIFT_FILES=()
while IFS= read -r -d '' file; do
  SWIFT_FILES+=("$file")
done < <(find Sources -type f -name '*.swift' -print0)

if [[ ${#SWIFT_FILES[@]} -eq 0 ]]; then
  printf 'NOT RUN: no Swift source files found under Sources/\n' >"$STATUS_FILE"
  exit 0
fi

# Run parse-only on the whole tree. The -parse action does not require
# resolvable imports; it stops after syntax + name binding.
if [[ "$SWIFT_BIN" == "swiftc" ]]; then
  PARSE_CMD=(swiftc -parse)
else
  PARSE_CMD=(swift -frontend -parse)
fi

if "${PARSE_CMD[@]}" "${SWIFT_FILES[@]}" >"$OUTPUT_FILE" 2>&1; then
  printf 'PASS: swift parse succeeded for %d files via %s\n' "${#SWIFT_FILES[@]}" "$SWIFT_BIN" >"$STATUS_FILE"
  exit 0
fi

printf 'FAIL: swift parse reported errors via %s\n' "$SWIFT_BIN" >"$STATUS_FILE"
cat "$OUTPUT_FILE" >&2
exit 1
