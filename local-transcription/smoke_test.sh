#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_BINARY="${SERVER_BINARY:-$SCRIPT_DIR/dist/bugnarrator-transcription}"
SMOKE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/bugnarrator-transcription-smoke.XXXXXX")"
AUDIO_PATH="$SMOKE_ROOT/fixture.aiff"
HEALTH_PATH="$SMOKE_ROOT/health.json"
RESPONSE_PATH="$SMOKE_ROOT/response.json"
SERVER_LOG_PATH="$SMOKE_ROOT/server.log"
SERVER_PID=""

cleanup() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi

    case "$SMOKE_ROOT" in
        "${TMPDIR:-/tmp}"/bugnarrator-transcription-smoke.*)
            rm -rf -- "$SMOKE_ROOT"
            ;;
    esac
}
trap cleanup EXIT

if [[ ! -x "$SERVER_BINARY" ]]; then
    echo "error: executable server not found at $SERVER_BINARY" >&2
    exit 1
fi

for command in curl say python3; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "error: $command is required for the transcription smoke test" >&2
        exit 1
    fi
done

PORT="${PORT:-$(python3 - <<'PY'
import socket

with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)}"

say -v Samantha -r 175 -o "$AUDIO_PATH" \
    "Bug Narrator local transcription is ready."

"$SERVER_BINARY" --host 127.0.0.1 --port "$PORT" --preload \
    >"$SERVER_LOG_PATH" 2>&1 &
SERVER_PID="$!"

for _ in $(seq 1 300); do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        cat "$SERVER_LOG_PATH" >&2
        echo "error: packaged transcription server exited before becoming healthy" >&2
        exit 1
    fi

    if curl --silent --show-error --max-time 2 \
        "http://127.0.0.1:$PORT/health" >"$HEALTH_PATH" 2>/dev/null \
        && python3 - "$HEALTH_PATH" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    health = json.load(handle)

raise SystemExit(0 if health.get("status") == "ok" and health.get("model_loaded") else 1)
PY
    then
        break
    fi
    sleep 1
done

if ! python3 - "$HEALTH_PATH" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        health = json.load(handle)
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)

raise SystemExit(0 if health.get("status") == "ok" and health.get("model_loaded") else 1)
PY
then
    cat "$SERVER_LOG_PATH" >&2
    echo "error: packaged transcription server did not preload within 300 seconds" >&2
    exit 1
fi

HTTP_STATUS="$(curl --silent --show-error --max-time 300 \
    --output "$RESPONSE_PATH" \
    --write-out '%{http_code}' \
    --form "file=@$AUDIO_PATH" \
    --form "model=parakeet-tdt-0.6b-v3" \
    --form "response_format=verbose_json" \
    "http://127.0.0.1:$PORT/v1/audio/transcriptions")"

if [[ "$HTTP_STATUS" != "200" ]]; then
    cat "$SERVER_LOG_PATH" >&2
    cat "$RESPONSE_PATH" >&2
    echo "error: packaged transcription request returned HTTP $HTTP_STATUS" >&2
    exit 1
fi

python3 - "$RESPONSE_PATH" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    response = json.load(handle)

text = response.get("text", "").strip().lower()
if not text or "bug" not in text or "narrator" not in text:
    print(json.dumps(response, indent=2), file=sys.stderr)
    raise SystemExit("packaged server returned an empty or incorrect smoke transcript")

print(f"Packaged transcription smoke test passed: {text}")
PY
