#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-$ROOT_DIR/build/DerivedData/Build/Products/Release/BugNarrator.app}"
APP_EXECUTABLE="${APP_EXECUTABLE:-$APP_PATH/Contents/MacOS/BugNarrator}"
LAUNCH_TIMEOUT_SECONDS="${LAUNCH_TIMEOUT_SECONDS:-8}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-1}"
LOG_PATH="${LOG_PATH:-$(mktemp -t bugnarrator-startup-smoke.XXXXXX.log)}"
APP_PROCESS_NAME="${APP_PROCESS_NAME:-BugNarrator}"
PROMPT_PROCESS_NAME="${PROMPT_PROCESS_NAME:-SecurityAgent}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: app not found at $APP_PATH" >&2
    exit 1
fi

if [[ ! -x "$APP_EXECUTABLE" ]]; then
    echo "error: app executable not found at $APP_EXECUTABLE" >&2
    exit 1
fi

cleanup() {
    local running_app_pids
    running_app_pids="$(app_pids_for_path)"
    if [[ -n "$running_app_pids" ]]; then
        while IFS= read -r app_pid; do
            kill "$app_pid" >/dev/null 2>&1 || true
        done <<<"$running_app_pids"
    fi

    if [[ -n "${NEW_PROMPT_PIDS:-}" ]]; then
        for prompt_pid in $NEW_PROMPT_PIDS; do
            kill "$prompt_pid" >/dev/null 2>&1 || true
        done
    fi
}

app_pids_for_path() {
    local pid command
    local matches=()
    while IFS= read -r pid; do
        [[ -z "$pid" ]] && continue
        command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
        if [[ "$command" == "$APP_EXECUTABLE"* ]]; then
            matches+=("$pid")
        fi
    done < <(pgrep -x "$APP_PROCESS_NAME" || true)

    printf '%s\n' "${matches[@]:-}" | sed '/^$/d'
}

trap cleanup EXIT

existing_prompt_pids="$(pgrep -x "$PROMPT_PROCESS_NAME" || true)"
pkill -x "$APP_PROCESS_NAME" >/dev/null 2>&1 || true
sleep 1

"$APP_EXECUTABLE" >"$LOG_PATH" 2>&1 &

deadline=$((SECONDS + LAUNCH_TIMEOUT_SECONDS))
app_started="NO"
while (( SECONDS < deadline )); do
    current_app_pids="$(app_pids_for_path)"
    if [[ -n "$current_app_pids" ]]; then
        app_started="YES"
    elif [[ "$app_started" == "YES" ]]; then
        echo "error: $APP_PROCESS_NAME exited during startup smoke test" >&2
        echo "Launch log: $LOG_PATH" >&2
        cat "$LOG_PATH" >&2 || true
        exit 1
    fi

    current_prompt_pids="$(pgrep -x "$PROMPT_PROCESS_NAME" || true)"
    NEW_PROMPT_PIDS="$(comm -13 <(printf '%s\n' "$existing_prompt_pids" | sed '/^$/d' | sort -u) <(printf '%s\n' "$current_prompt_pids" | sed '/^$/d' | sort -u) || true)"
    if [[ -n "$NEW_PROMPT_PIDS" ]]; then
        echo "error: detected new $PROMPT_PROCESS_NAME process during startup smoke test" >&2
        echo "Launch log: $LOG_PATH" >&2
        cat "$LOG_PATH" >&2 || true
        exit 1
    fi

    sleep "$POLL_INTERVAL_SECONDS"
done

if [[ "$app_started" != "YES" ]]; then
    echo "error: $APP_PROCESS_NAME did not stay running during startup smoke test" >&2
    echo "Launch log: $LOG_PATH" >&2
    cat "$LOG_PATH" >&2 || true
    exit 1
fi

echo "Startup keychain smoke test passed."
echo "App path: $APP_PATH"
echo "Launch log: $LOG_PATH"
