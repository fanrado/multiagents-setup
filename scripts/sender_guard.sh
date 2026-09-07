#!/usr/bin/env bash
# Sender identity + the orchestrator send-block, shared by the scripts that
# type into another agent's pane (dispatch.sh, msg.sh, notify.sh).
#
# The orchestrator is a *receiving-only* role. It talks to the human, and the
# human is the only one who may put words into another agent's chat on its
# behalf. Unprompted orchestrator messages are invisible to the human in
# detail yet land in the recipient as instructions it will act on, outside the
# plan the human approved — which has created new problems instead of solving
# the original one.
#
# agents/orchestrator.md states that rule, but a written instruction is
# something a model can talk itself out of. This is the enforcement: the block
# lives in the scripts, so it holds no matter what the orchestrator session
# decides, and there is deliberately no environment escape hatch (an env var
# the orchestrator could set is not a block). The human sends from a plain
# terminal, where the caller role is `user` — never blocked.

# Role of the pane this script was called from, or "user" outside the
# workspace. $TMUX_PANE is set by tmux in every pane and survives into the
# claude session and its Bash-tool subprocesses, so a caller passes nothing.
caller_role() {
    local role=""
    if [[ -n "${TMUX_PANE:-}" ]]; then
        role=$(tmux display-message -p -t "$TMUX_PANE" "#{@role}" 2>/dev/null || true)
    fi
    [[ -z "$role" ]] && role="user"
    printf '%s' "$role"
}

# Refuse to run when the caller is the orchestrator pane. $1 is the script
# name, used only in the message.
deny_orchestrator_send() {
    local script="$1"
    [[ "$(caller_role)" == "${PANE_ORCHESTRATOR:-orchestrator}" ]] || return 0

    cat >&2 <<MSG
$script: blocked — the orchestrator may not send text to another agent.

The orchestrator plans and receives; it does not push messages or dispatch.
Work reaches the developer as a beads issue the human approved: create it
with 'bd create', and the developer's poll of 'bd ready' picks it up on its
next idle cycle. Nothing needs to be typed into its pane.

If something really must be said to another agent, tell the human what you
would say and let them send it themselves.
MSG
    exit 1
}
