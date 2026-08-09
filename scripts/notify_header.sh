#!/usr/bin/env bash
# Update the orchestrator pane title with a status message from an agent,
# and flash it on the status line so the event surfaces immediately.
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

# Flash the message on the status line for 4 seconds.
#
# NOT a display-popup: a popup is modal — it grabs the keyboard until it is
# dismissed, so the pane underneath cannot be typed into. Agents notify on
# every finished run, and several notifications in a row (or one agent in a
# restart loop) turn that into a window that keeps reappearing on top and
# locks the user out of the whole workspace. display-message is transient
# and steals no input; @status above keeps the message visible afterwards.
tmux display-message -t "$SESSION" -d 4000 "$MESSAGE" 2>/dev/null || true
