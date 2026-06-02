#!/usr/bin/env bash
# Developer agent — starts an interactive Claude session that loops through open beads issues.
# Interactive mode (no -p) so all tool calls, logs, and output are visible in the pane.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$WORKSPACE_ROOT/config/workspace.conf"
source "$WORKSPACE_ROOT/scripts/preflight.sh"

bd() { (cd "$WORKSPACE_DIR" && command bd "$@"); }

INSTRUCTIONS="$WORKSPACE_ROOT/agents/developer.md"

echo "[developer] WORKSPACE_ROOT : $WORKSPACE_ROOT"
echo "[developer] WORKSPACE_DIR  : $WORKSPACE_DIR"

# Determine initial prompt based on git/beads state inherited from workspace.sh
if [[ -n "${NO_BEADS:-}" ]]; then
    echo "[developer] beads not available — starting in no-tracking mode"
    INITIAL_PROMPT="No beads issue tracker is available. Explore $WORKSPACE_DIR, understand the codebase, and wait for direct instructions."
else
    open_count=$(preflight_count_issues "$WORKSPACE_DIR" || echo 0)
    if [[ "$open_count" -eq 0 ]]; then
        echo "[developer] No open issues — Claude will poll and wait"
        INITIAL_PROMPT="There are no open beads issues right now. Run 'bd ready' every 30 seconds. As soon as an issue appears, read it with 'bd show <id>', implement the feature in $WORKSPACE_DIR, commit your changes, then close it with 'bd close <id>'. Keep looping until there is nothing left to do."
    else
        echo "[developer] $open_count open issue(s) found — starting work"
        INITIAL_PROMPT="Start your work session: run 'bd ready' to find open issues (skip any titled 'test report'). For each open issue, read it with 'bd show <id>', implement the feature in $WORKSPACE_DIR, commit your changes, then close the issue with 'bd close <id>'. After each issue, immediately check 'bd ready' again and continue. Keep going until there is nothing left to do, then wait."
    fi
fi

echo "[developer] Starting Claude (interactive)..."

exec claude \
    --dangerously-skip-permissions \
    --add-dir "$WORKSPACE_DIR" \
    --append-system-prompt "$(cat "$INSTRUCTIONS")" \
    "$INITIAL_PROMPT"
