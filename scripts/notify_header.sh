#!/usr/bin/env bash
# Update the orchestrator pane title with a status message from an agent,
# and show a brief auto-dismissing popup so the event surfaces immediately.
# Usage: notify_header.sh <session> <message>
set -euo pipefail

SESSION="${1:?Usage: notify_header.sh <session> <message>}"
MESSAGE="${2:?Usage: notify_header.sh <session> <message>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../config/workspace.conf"
# shellcheck source=./tmux_helpers.sh
source "$SCRIPT_DIR/tmux_helpers.sh"

ORCH_PANE=$(tmux_find_pane_by_role "$SESSION" "$PANE_ORCHESTRATOR")

[[ -z "$ORCH_PANE" ]] && exit 0

# Publish the status as @status, which pane-border-format appends after the
# role name. Overwriting the pane title instead would erase the "orchestrator"
# label and used to break every title-based pane lookup.
tmux set-option -p -t "$ORCH_PANE" @status "$MESSAGE"

# Show a 4-second auto-dismissing popup (tmux >= 3.2)
tmux display-popup \
    -t "$SESSION" \
    -w "50%" -h "20%" \
    -T " Agent Update " \
    -E "printf '\\n  %s\\n' \"$MESSAGE\"; sleep 4" 2>/dev/null || true
