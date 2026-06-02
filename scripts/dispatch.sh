#!/usr/bin/env bash
# Dispatch work to the developer agent (tab 2).
# Usage:
#   dispatch.sh <issue-id> [session-name]          # dispatch a beads issue (marks in_progress)
#   dispatch.sh -m "message" [session-name]        # send a free-form prompt to the developer tab
#   dispatch.sh --message "message" [session-name]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config/workspace.conf
source "$SCRIPT_DIR/../config/workspace.conf"

FREE_FORM_MSG=""
ISSUE_ID=""

# Parse arguments
case "${1:-}" in
    -m|--message)
        FREE_FORM_MSG="${2:?--message requires a message string}"
        SESSION="${3:-$SESSION_NAME}"
        ;;
    "")
        echo "Usage: dispatch.sh <issue-id> [session-name]" >&2
        echo "       dispatch.sh -m \"message\" [session-name]" >&2
        exit 1
        ;;
    *)
        ISSUE_ID="$1"
        SESSION="${2:-$SESSION_NAME}"
        ;;
esac

# Locate the developer pane by title
DEV_PANE=$(tmux list-panes -t "$SESSION" -F "#{pane_id} #{pane_title}" \
    | awk -v title="$PANE_DEVELOPER" '$2 == title { print $1; exit }')

if [[ -z "$DEV_PANE" ]]; then
    echo "dispatch.sh: developer pane not found in session '$SESSION'." >&2
    echo "  Is the workspace running? Start it with: ./workspace.sh -s $SESSION" >&2
    exit 1
fi

if [[ -n "$FREE_FORM_MSG" ]]; then
    # Send the message directly as a Claude Code prompt
    tmux send-keys -t "$DEV_PANE" "$FREE_FORM_MSG" Enter
    echo "Sent to developer pane: $FREE_FORM_MSG"
else
    # Verify the issue exists
    if ! bd show "$ISSUE_ID" &>/dev/null; then
        echo "dispatch.sh: issue '$ISSUE_ID' not found." >&2
        exit 1
    fi

    # Mark the issue in_progress so agents and user can see it's been dispatched
    bd update "$ISSUE_ID" --status=in_progress 2>/dev/null || true

    # Send a natural-language prompt to the Claude agent in the developer pane
    tmux send-keys -t "$DEV_PANE" \
        ">>> [DISPATCH] New issue ready: $ISSUE_ID — run 'bd show $ISSUE_ID' to read it, then implement the feature." \
        Enter

    echo "Dispatched $ISSUE_ID to developer pane in session '$SESSION'."
fi
