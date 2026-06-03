#!/usr/bin/env bash
# Tester agent — runs Claude in a restart loop so it stays alive between commits.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$WORKSPACE_ROOT/config/workspace.conf"

bd() { (cd "$WORKSPACE_DIR" && command bd "$@"); }

INSTRUCTIONS="$WORKSPACE_ROOT/agents/tester.md"
STATE_DIR="${TMPDIR:-/tmp}/multiagents-${SESSION_NAME}"
HEAD_FILE="$STATE_DIR/tester-head"
LOG_FILE="$STATE_DIR/watcher.log"
mkdir -p "$STATE_DIR"

# Seed with current HEAD so we don't re-test commits that predate this session.
git -C "$WORKSPACE_DIR" rev-parse HEAD 2>/dev/null > "$HEAD_FILE" || echo "" > "$HEAD_FILE"

echo "[tester] WORKSPACE_ROOT : $WORKSPACE_ROOT"
echo "[tester] WORKSPACE_DIR  : $WORKSPACE_DIR"
echo "[tester] git watching   : $WORKSPACE_DIR"
echo "[tester] bd runs from   : $WORKSPACE_DIR"

POLL_PROMPT="No new commits right now. Run 'git -C $WORKSPACE_DIR log --oneline -1' every 30 seconds. As soon as a new commit appears that you haven't tested yet, write tests for it and report results via beads. Keep looping."

echo "[tester] Starting Claude (restart loop)..."

while true; do
    current_head=$(git -C "$WORKSPACE_DIR" rev-parse HEAD 2>/dev/null || echo "")
    last_head=$(cat "$HEAD_FILE" 2>/dev/null || echo "")

    if [[ -n "$current_head" && "$current_head" != "$last_head" ]]; then
        echo "$current_head" > "$HEAD_FILE"
        short=$(git -C "$WORKSPACE_DIR" log -1 --pretty=format:"%s (%h)" 2>/dev/null || echo "$current_head")
        diff_stat=$(git -C "$WORKSPACE_DIR" show --stat HEAD 2>/dev/null | head -20 || echo "")

        PROMPT="New commit detected: $short

Changed files:
$diff_stat

Write tests for the new feature and run the test suite in $WORKSPACE_DIR. Follow your instructions."
        echo "[tester] New commit: $short — starting Claude..."
        work=true
    else
        PROMPT="$POLL_PROMPT"
        echo "[tester] No new commits — Claude will poll and wait"
        work=false
    fi

    if $work; then
        echo "[tester $(date +%H:%M:%S)] === test run: $short ===" >> "$LOG_FILE"
        claude \
            --dangerously-skip-permissions \
            --add-dir "$WORKSPACE_DIR" \
            --append-system-prompt "$(cat "$INSTRUCTIONS")" \
            "$PROMPT" 2>&1 | tee -a "$LOG_FILE" || true
        echo "[tester $(date +%H:%M:%S)] === done ===" >> "$LOG_FILE"
        ts=$(date +%H:%M)
        "$SCRIPT_DIR/../../scripts/notify_header.sh" "$SESSION_NAME" \
            "[tester] Tests done: $short ($ts)" 2>/dev/null || true
    else
        claude \
            --dangerously-skip-permissions \
            --add-dir "$WORKSPACE_DIR" \
            --append-system-prompt "$(cat "$INSTRUCTIONS")" \
            "$PROMPT" || true
    fi

    echo "[tester] Claude exited. Restarting in 15s..."
    sleep 15
done
