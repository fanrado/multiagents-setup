#!/usr/bin/env bash
# Send a free-form message from one agent to another.
#
# dispatch.sh and notify.sh cover the two fixed edges of the routine workflow
# (orchestrator -> developer, anyone -> orchestrator). This script covers
# everything else: any role asking any other role a specific, off-script
# question — "which fixture does test_foo use?", "is the API surface final?" —
# without the asker hand-rolling tmux send-keys.
#
# Usage:
#   msg.sh <to-role> <message> [session-name]
#
#   <to-role>  orchestrator | developer | tester | debugger
#
# The sender is inferred from the calling pane's @role stamp, so the recipient
# always knows who to answer.
set -euo pipefail

usage() {
    echo "Usage: msg.sh <to-role> <message> [session-name]" >&2
    echo "  <to-role>: orchestrator | developer | tester | debugger" >&2
}

TO_ROLE="${1:-}"
MESSAGE="${2:-}"

if [[ -z "$TO_ROLE" || -z "$MESSAGE" ]]; then
    usage
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config/workspace.conf
source "$SCRIPT_DIR/../config/workspace.conf"
# shellcheck source=./tmux_helpers.sh
source "$SCRIPT_DIR/tmux_helpers.sh"

SESSION="${3:-$SESSION_NAME}"

case "$TO_ROLE" in
    "$PANE_ORCHESTRATOR"|"$PANE_DEVELOPER"|"$PANE_TESTER"|"$PANE_DEBUGGER") ;;
    *)
        echo "msg.sh: unknown role '$TO_ROLE'" >&2
        usage
        exit 1
        ;;
esac

# Resolve the recipient by its @role stamp — pane titles are rewritten by the
# claude session running inside the pane, so they are not addressable.
# `|| true`: tmux_find_pane_by_role pipes tmux into awk, and under `set -o
# pipefail` a missing session makes the whole substitution fail, killing the
# script under `set -e` before the friendly message below can print.
TARGET_PANE=$(tmux_find_pane_by_role "$SESSION" "$TO_ROLE" || true)

if [[ -z "$TARGET_PANE" ]]; then
    echo "msg.sh: '$TO_ROLE' pane not found in session '$SESSION'." >&2
    echo "  Is the workspace running? Start it with: ./workspace.sh -s $SESSION" >&2
    exit 1
fi

# Identify the sender. $TMUX_PANE is set by tmux in every pane, and survives
# into the claude session and its Bash-tool subprocesses, so an agent calling
# this script needs to pass nothing. Fall back to "user" when called from
# outside the workspace (a plain terminal has no @role).
FROM_ROLE="unknown"
if [[ -n "${TMUX_PANE:-}" ]]; then
    FROM_ROLE=$(tmux display-message -p -t "$TMUX_PANE" "#{@role}" 2>/dev/null || true)
fi
[[ -z "$FROM_ROLE" ]] && FROM_ROLE="user"

if [[ "$FROM_ROLE" == "$TO_ROLE" ]]; then
    echo "msg.sh: refusing to send a message to yourself ($TO_ROLE)" >&2
    exit 1
fi

# Deliver as a plain-text prompt: every agent pane runs an interactive `claude`
# session, so this lands as a real chat message rather than a shell command.
tmux send-keys -t "$TARGET_PANE" \
    ">>> [MSG from $FROM_ROLE] $MESSAGE" Enter

echo "Sent to $TO_ROLE (from $FROM_ROLE): $MESSAGE"
