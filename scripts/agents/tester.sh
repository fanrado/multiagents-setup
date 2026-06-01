#!/usr/bin/env bash
# Launch the tester agent (Claude Code) in the current pane.
# Expected to run inside the tester tmux pane on the test/<name> branch.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../../config/workspace.conf
source "$WORKSPACE_ROOT/config/workspace.conf"

INSTRUCTIONS="$WORKSPACE_ROOT/agents/tester.md"

exec claude \
    --dangerously-skip-permissions \
    --append-system-prompt "$(cat "$INSTRUCTIONS")"
