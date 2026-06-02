#!/usr/bin/env bash
# Update the orchestrator pane title with a status message from an agent.
# Usage: notify_header.sh <session> <message>
# The message appears in the orchestrator pane's border header.
set -euo pipefail

SESSION="${1:?Usage: notify_header.sh <session> <message>}"
MESSAGE="${2:?Usage: notify_header.sh <session> <message>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/workspace.conf"

ORCH_PANE=$(tmux list-panes -t "$SESSION" -F "#{pane_id} #{pane_title}" 2>/dev/null \
    | awk -v t="$PANE_ORCHESTRATOR" '$2 == t { print $1; exit }')

[[ -z "$ORCH_PANE" ]] && exit 0

tmux select-pane -t "$ORCH_PANE" -T "$MESSAGE"
