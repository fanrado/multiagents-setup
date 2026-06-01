#!/usr/bin/env bash
# Launch the developer agent (Claude Code) in the current pane.
# Expected to run inside the developer tmux pane on the features/<name> branch.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=../../config/workspace.conf
source "$WORKSPACE_ROOT/config/workspace.conf"

INSTRUCTIONS="$WORKSPACE_ROOT/agents/developer.md"

exec claude \
    --dangerously-skip-permissions \
    --append-system-prompt "$(cat "$INSTRUCTIONS")"
