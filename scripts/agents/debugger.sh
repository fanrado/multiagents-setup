#!/usr/bin/env bash
# Debugger agent — idles until the tester opens a "test report" beads issue,
# then starts an interactive Claude session to fix the failures on test/<name>.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$WORKSPACE_ROOT/config/workspace.conf"

bd() { (cd "$WORKSPACE_DIR" && command bd "$@"); }

INSTRUCTIONS="$WORKSPACE_ROOT/agents/debugger.md"
POLL_INTERVAL="${DEBUGGER_POLL_INTERVAL:-10}"
STATE_DIR="${TMPDIR:-/tmp}/multiagents-${SESSION_NAME}"
SEEN_FILE="$STATE_DIR/debugger-seen"
mkdir -p "$STATE_DIR"
touch "$SEEN_FILE"

echo "[debugger] WORKSPACE_ROOT : $WORKSPACE_ROOT"
echo "[debugger] WORKSPACE_DIR  : $WORKSPACE_DIR"
echo "[debugger] bd runs from   : $WORKSPACE_DIR"
echo "[debugger] Waiting for test report issues every ${POLL_INTERVAL}s..."

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

        echo "[debugger] Test report found: $report — starting Claude on test/<name> branch..."
        claude \
            --dangerously-skip-permissions \
            --add-dir "$WORKSPACE_DIR" \
            --append-system-prompt "$(cat "$INSTRUCTIONS")" \
            "A new failing test report has been filed: $report

$details

You are on the test/<name> branch. Diagnose and fix the failing tests in $WORKSPACE_DIR following your instructions. Do not touch production code unless it contains a clear bug."

        echo "[debugger] Claude session done. Waiting for next test report..."
    else
        sleep "$POLL_INTERVAL"
    fi
done
