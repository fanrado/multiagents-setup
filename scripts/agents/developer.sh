#!/usr/bin/env bash
# Developer agent — starts an interactive Claude session that loops through open beads issues.
# Interactive mode (no -p) so all tool calls, logs, and output are visible in the pane.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$WORKSPACE_ROOT/config/workspace.conf"

bd() { (cd "$WORKSPACE_DIR" && command bd "$@"); }

INSTRUCTIONS="$WORKSPACE_ROOT/agents/developer.md"

echo "[developer] WORKSPACE_ROOT : $WORKSPACE_ROOT"
echo "[developer] WORKSPACE_DIR  : $WORKSPACE_DIR"
echo "[developer] Starting Claude (interactive)..."

exec claude \
    --dangerously-skip-permissions \
    --add-dir "$WORKSPACE_DIR" \
    --append-system-prompt "$(cat "$INSTRUCTIONS")" \
    "Start your work session: run 'bd ready' to find open issues (skip any titled 'test report'). For each open issue, read it with 'bd show <id>', implement the feature in $WORKSPACE_DIR, commit your changes, then close the issue with 'bd close <id>'. After each issue, immediately check 'bd ready' again and continue. Keep going until there is nothing left to do, then wait."
