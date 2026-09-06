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
# shellcheck source=./tmux_helpers.sh
source "$SCRIPT_DIR/tmux_helpers.sh"
# shellcheck source=./idle.sh
source "$SCRIPT_DIR/idle.sh"

# Run bd against the project repo (WORKSPACE_DIR), not dispatch.sh's ambient cwd,
# which may differ when the workspace was started with -d/--dir.
bd() { (cd "$WORKSPACE_DIR" && command bd "$@"); }

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

# Locate the developer pane by its @role stamp — the pane title is not stable,
# claude rewrites it with whatever task it is currently working on.
DEV_PANE=$(tmux_find_pane_by_role "$SESSION" "$PANE_DEVELOPER")

if [[ -z "$DEV_PANE" ]]; then
    echo "dispatch.sh: developer pane not found in session '$SESSION'." >&2
    echo "  Is the workspace running? Start it with: ./workspace.sh -s $SESSION" >&2
    exit 1
fi

# A pane parked in its idle wait (scripts/idle_wait.sh) is inside a blocking
# Bash tool call: anything typed now would only queue until that call returns,
# minutes later. Interrupt it first — but only when its heartbeat proves it is
# just sleeping, never when it might be mid-implementation.
agent_wake_pane "$DEV_PANE" "$PANE_DEVELOPER" "$SESSION" \
    && echo "dispatch.sh: developer was idle-waiting — interrupted it so this is read now."

if [[ -n "$FREE_FORM_MSG" ]]; then
    # Send the message directly as a Claude Code prompt.
    # Messages are for questions and course corrections, not for handing off
    # work: nothing about a message survives a pane restart, and the developer
    # only finds work by polling beads. Work goes out as an issue id.
    tmux send-keys -t "$DEV_PANE" "$FREE_FORM_MSG" Enter
    echo "Sent to developer pane: $FREE_FORM_MSG"
else
    # Verify the issue exists
    if ! bd show "$ISSUE_ID" &>/dev/null; then
        echo "dispatch.sh: issue '$ISSUE_ID' not found." >&2
        exit 1
    fi

    # Leave the issue OPEN. It used to be flipped to in_progress here, which
    # hid it from `bd ready` — the very query the developer's idle loop polls.
    # A dispatch keystroke that arrived queued (or got lost with the pane) then
    # had no backstop: the loop could no longer see the issue it was told to
    # work on, and idled instead. The developer claims the issue when it
    # actually starts (see agents/developer.md).
    if ! bd ready 2>/dev/null | grep -q "$ISSUE_ID"; then
        echo "dispatch.sh: warning — $ISSUE_ID is not in 'bd ready' (blocked, claimed or closed?)." >&2
        echo "  The developer polls 'bd ready', so it will not pick this up on its own." >&2
    fi

    # Send a natural-language prompt to the Claude agent in the developer pane
    tmux send-keys -t "$DEV_PANE" \
        ">>> [DISPATCH] New issue ready: $ISSUE_ID — run 'bd show $ISSUE_ID' to read it, claim it with 'bd update $ISSUE_ID --status=in_progress', then implement the feature." \
        Enter

    echo "Dispatched $ISSUE_ID to developer pane in session '$SESSION'."
fi
