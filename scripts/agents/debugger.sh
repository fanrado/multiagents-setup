#!/usr/bin/env bash
# Debugger agent — runs Claude in a restart loop so it stays alive between test reports.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$WORKSPACE_ROOT/config/workspace.conf"

bd() { (cd "$WORKSPACE_DIR" && command bd "$@"); }

INSTRUCTIONS="$WORKSPACE_ROOT/agents/debugger.md"
STATE_DIR="${TMPDIR:-/tmp}/multiagents-${SESSION_NAME}"
SEEN_FILE="$STATE_DIR/debugger-seen"
mkdir -p "$STATE_DIR"
touch "$SEEN_FILE"

echo "[debugger] WORKSPACE_ROOT : $WORKSPACE_ROOT"
echo "[debugger] WORKSPACE_DIR  : $WORKSPACE_DIR"
echo "[debugger] bd runs from   : $WORKSPACE_DIR"

POLL_PROMPT="No open test report issues right now. Run 'bd list --status=open' every 30 seconds. As soon as a 'Test report' issue appears, read it with 'bd show <id>', diagnose and fix the failures, then close the issue. Keep looping."

echo "[debugger] Starting Claude (restart loop)..."

while true; do
    # Look for open test-report issues not yet handled by this session
    report=$(bd list --status=open 2>/dev/null \
        | grep -i 'test.report' \
        | grep -o 'beads-[^ ]*\|[0-9a-zA-Z_-]*test[0-9a-zA-Z_-]*' \
        | head -1 || true)

    # Fallback: read directly from JSONL export
    if [[ -z "$report" ]]; then
        report=$(grep '"status":"open"' "$WORKSPACE_DIR/.beads/issues.jsonl" 2>/dev/null \
            | grep -i 'test.report\|test report' \
            | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
    fi

    if [[ -n "$report" ]] && ! grep -qxF "$report" "$SEEN_FILE"; then
        echo "$report" >> "$SEEN_FILE"
        details=$(bd show "$report" 2>/dev/null || echo "(could not load report)")

        PROMPT="A new failing test report has been filed: $report

$details

You are on the test/<name> branch. Diagnose and fix the failing tests in $WORKSPACE_DIR following your instructions. Do not touch production code unless it contains a clear bug."
        echo "[debugger] Test report found: $report — starting Claude..."
        work=true
    else
        PROMPT="$POLL_PROMPT"
        echo "[debugger] No test reports — Claude will poll and wait"
        work=false
    fi

    claude \
        --dangerously-skip-permissions \
        --add-dir "$WORKSPACE_DIR" \
        --append-system-prompt "$(cat "$INSTRUCTIONS")" \
        "$PROMPT" || true

    if $work; then
        ts=$(date +%H:%M)
        "$SCRIPT_DIR/../../scripts/notify_header.sh" "$SESSION_NAME" \
            "[debugger] Fixed: $report ($ts)" 2>/dev/null || true
    fi

    echo "[debugger] Claude exited. Restarting in 15s..."
    sleep 15
done
