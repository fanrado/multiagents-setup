#!/usr/bin/env bash
# Send a visible notification message to the orchestrator pane (tab 1).
# Usage: notify.sh <session> <message>
set -euo pipefail

SESSION="${1:?Usage: notify.sh <session> <message>}"
MESSAGE="${2:?Usage: notify.sh <session> <message>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config/workspace.conf
source "$SCRIPT_DIR/../config/workspace.conf"

# Locate the orchestrator pane by title
ORCH_PANE=$(tmux list-panes -t "$SESSION" -F "#{pane_id} #{pane_title}" \
    | awk -v title="$PANE_ORCHESTRATOR" '$2 == title { print $1; exit }')

if [[ -z "$ORCH_PANE" ]]; then
    echo "notify.sh: orchestrator pane not found in session '$SESSION'" >&2
    exit 1
fi

# Send as a plain-text prompt, not a shell command: the orchestrator pane
# runs an interactive `claude` session (see scripts/agents/orchestrator.sh),
# so this becomes a real message in its chat, same as dispatch.sh does for
# the developer pane.
tmux send-keys -t "$ORCH_PANE" \
    ">>> [AGENT ALERT] $MESSAGE" Enter
