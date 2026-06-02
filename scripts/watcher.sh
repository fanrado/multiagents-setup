#!/usr/bin/env bash
# Background event loop — logs workspace activity and exits when the session ends.
# Agents (developer, tester, debugger) are self-driving via polling loops;
# this watcher exists only for visibility and orchestrator notifications.
#
# Launched by workspace.sh; exits automatically when the tmux session ends.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$WORKSPACE_ROOT/config/workspace.conf"

POLL_INTERVAL="${WATCHER_INTERVAL:-5}"
_state="${TMPDIR:-/tmp}/multiagents-${SESSION_NAME}"
mkdir -p "$_state"

SEEN_FILE="$_state/seen-issues"         # tracks logged open issues
CLOSED_FILE="$_state/seen-closed"       # tracks issues already notified as closed
HEAD_FILE="$_state/watcher-head"        # tracks logged commits
PID_FILE="$_state/watcher.pid"
LOG_FILE="$_state/watcher.log"

# Prevent duplicate watchers for the same session
if [[ -f "$PID_FILE" ]]; then
    old_pid=$(cat "$PID_FILE")
    if kill -0 "$old_pid" 2>/dev/null; then
        echo "Watcher already running (PID $old_pid). Exiting." >&2
        exit 0
    fi
fi
echo $$ > "$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT

# Redirect output to log file (tail -f "$LOG_FILE" to observe)
exec >> "$LOG_FILE" 2>&1

log() { echo "[watcher $(date +%H:%M:%S)] $*"; }

_pane() {
    tmux list-panes -t "$SESSION_NAME" -F "#{pane_id} #{pane_title}" 2>/dev/null \
        | awk -v t="$1" '$2 == t { print $1; exit }'
}

# Seed seen-issues with non-open issues only.
# Open issues are left unseeded so the developer is dispatched them on the first poll.
touch "$SEEN_FILE"
# Seed closed-issues so we don't notify about work that predates this session.
touch "$CLOSED_FILE"
if [[ -f "$WORKSPACE_ROOT/.beads/issues.jsonl" ]]; then
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        id=$(echo "$line"     | grep -o '"id":"[^"]*"'     | head -1 | cut -d'"' -f4)
        status=$(echo "$line" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
        [[ -z "$id" ]] && continue
        if [[ "$status" != "open" ]]; then
            echo "$id" >> "$SEEN_FILE"
            echo "$id" >> "$CLOSED_FILE"
        fi
    done < "$WORKSPACE_ROOT/.beads/issues.jsonl"
fi

# Seed HEAD from the project repo (WORKSPACE_DIR), not the setup repo
git -C "$WORKSPACE_DIR" rev-parse HEAD 2>/dev/null > "$HEAD_FILE" || echo "" > "$HEAD_FILE"

log "Started (PID $$, session=$SESSION_NAME, interval=${POLL_INTERVAL}s)"
log "Log: $LOG_FILE"

while tmux has-session -t "$SESSION_NAME" 2>/dev/null; do
    sleep "$POLL_INTERVAL"

    # ── Log new open beads issues; notify orchestrator when issues close ────────
    if [[ -f "$WORKSPACE_ROOT/.beads/issues.jsonl" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            id=$(echo "$line"     | grep -o '"id":"[^"]*"'     | head -1 | cut -d'"' -f4)
            status=$(echo "$line" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
            title=$(echo "$line"  | grep -o '"title":"[^"]*"'  | head -1 | cut -d'"' -f4)
            [[ -z "$id" ]] && continue

            if [[ "$status" == "open" ]]; then
                grep -qxF "$id" "$SEEN_FILE" && continue
                echo "$id" >> "$SEEN_FILE"
                log "New open issue: $id — $title"
                "$SCRIPT_DIR/dispatch.sh" "$id" "$SESSION_NAME" 2>/dev/null \
                    && log "Dispatched $id to developer" \
                    || log "dispatch failed for $id (developer pane not ready?)"
            elif [[ "$status" == "closed" ]]; then
                grep -qxF "$id" "$CLOSED_FILE" && continue
                echo "$id" >> "$CLOSED_FILE"
                ts=$(date +%H:%M)
                log "Issue closed: $id — $title"
                "$SCRIPT_DIR/notify_header.sh" "$SESSION_NAME" \
                    "[developer] Done: $title ($ts)" 2>/dev/null || true
            fi
        done < "$WORKSPACE_ROOT/.beads/issues.jsonl"
    fi

    # ── Log new git commits ──────────────────────────────────────────────────
    current_head=$(git -C "$WORKSPACE_DIR" rev-parse HEAD 2>/dev/null || echo "")
    last_head=$(cat "$HEAD_FILE" 2>/dev/null || echo "")
    if [[ -n "$current_head" && "$current_head" != "$last_head" ]]; then
        echo "$current_head" > "$HEAD_FILE"
        short=$(git -C "$WORKSPACE_DIR" log -1 --pretty=format:"%s (%h)" 2>/dev/null \
                || echo "$current_head")
        log "New commit: $short"
    fi
done

log "Session '$SESSION_NAME' ended. Watcher exiting."
