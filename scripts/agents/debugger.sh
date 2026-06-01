#!/usr/bin/env bash
# Launch the debugger agent (Claude Code) in the current pane.
# Expected to run inside the debugger tmux pane on the test/<name> branch.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../../config/workspace.conf
source "$WORKSPACE_ROOT/config/workspace.conf"

INSTRUCTIONS="$WORKSPACE_ROOT/agents/debugger.md"

exec claude \
    --dangerously-skip-permissions \
    --append-system-prompt "$(cat "$INSTRUCTIONS")"
