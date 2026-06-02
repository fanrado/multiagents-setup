#!/usr/bin/env bash
# Tester agent — watches WORKSPACE_DIR for new commits and runs tests on each one.
# Interactive Claude (no -p) so all output is visible in the pane.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$WORKSPACE_ROOT/config/workspace.conf"

bd() { (cd "$WORKSPACE_DIR" && command bd "$@"); }

INSTRUCTIONS="$WORKSPACE_ROOT/agents/tester.md"
POLL_INTERVAL="${TESTER_POLL_INTERVAL:-10}"
STATE_DIR="${TMPDIR:-/tmp}/multiagents-${SESSION_NAME}"
HEAD_FILE="$STATE_DIR/tester-head"
mkdir -p "$STATE_DIR"

# Seed with current HEAD so we don't re-test commits that predate this session.
git -C "$WORKSPACE_DIR" rev-parse HEAD 2>/dev/null > "$HEAD_FILE" || echo "" > "$HEAD_FILE"

echo "[tester] WORKSPACE_ROOT : $WORKSPACE_ROOT"
echo "[tester] WORKSPACE_DIR  : $WORKSPACE_DIR"
echo "[tester] git watching   : $WORKSPACE_DIR"
echo "[tester] bd runs from   : $WORKSPACE_DIR"
echo "[tester] Watching for new commits every ${POLL_INTERVAL}s..."

while true; do
    current_head=$(git -C "$WORKSPACE_DIR" rev-parse HEAD 2>/dev/null || echo "")
    last_head=$(cat "$HEAD_FILE" 2>/dev/null || echo "")

    if [[ -n "$current_head" && "$current_head" != "$last_head" ]]; then
        echo "$current_head" > "$HEAD_FILE"
        short=$(git -C "$WORKSPACE_DIR" log -1 --pretty=format:"%s (%h)" 2>/dev/null || echo "$current_head")
        diff_stat=$(git -C "$WORKSPACE_DIR" show --stat HEAD 2>/dev/null | head -20 || echo "")

        echo "[tester] New commit: $short — starting Claude..."
        claude \
            --dangerously-skip-permissions \
            --add-dir "$WORKSPACE_DIR" \
            --append-system-prompt "$(cat "$INSTRUCTIONS")" \
            "New commit detected: $short

Changed files:
$diff_stat

Write tests for the new feature and run the test suite in $WORKSPACE_DIR. Follow your instructions."

        echo "[tester] Claude session done. Watching for next commit..."
    else
        sleep "$POLL_INTERVAL"
    fi
done
