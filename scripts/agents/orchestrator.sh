#!/usr/bin/env bash
# Orchestrator agent — launches Claude once for the human-driven planning pane.
# Unlike developer/tester/debugger, this pane is interactive and human-present,
# so it runs once (no restart loop, no --dangerously-skip-permissions) and then
# hands the terminal back to the human on exit.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$WORKSPACE_ROOT/config/workspace.conf"

INSTRUCTIONS="$WORKSPACE_ROOT/agents/orchestrator.md"

echo "[orchestrator] WORKSPACE_ROOT : $WORKSPACE_ROOT"
echo "[orchestrator] WORKSPACE_DIR  : $WORKSPACE_DIR"

exec claude \
    --add-dir "$WORKSPACE_DIR" \
    --append-system-prompt "$(cat "$INSTRUCTIONS")"
