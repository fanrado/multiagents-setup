#!/usr/bin/env bash
# Shared idle-poll heartbeat convention.
#
# An agent pane with no work parks inside one long, self-blocking loop
# (scripts/idle_wait.sh) that it runs through claude's own Bash tool. While
# that tool call is running, text typed into the pane by dispatch.sh or msg.sh
# does not become a prompt — claude queues it until the call returns, which can
# be minutes later. That is what "the orchestrator dispatched, but the
# developer took forever to start" actually was.
#
# So idle_wait.sh stamps a heartbeat file once per wait iteration, and a sender
# checks it: a fresh stamp means the pane is parked in `sleep` and Escape is
# safe (it costs an idle iteration and nothing else); a stale or missing stamp
# means the pane is working or at its prompt, and must not be interrupted.

# Interval and window shared by every idle wait loop.
export AGENT_IDLE_INTERVAL="${AGENT_IDLE_INTERVAL:-30}"
export AGENT_IDLE_CYCLES="${AGENT_IDLE_CYCLES:-15}"

# A heartbeat older than this is not proof of an idle pane. One interval plus
# slack: the stamp is written just before each sleep.
export AGENT_IDLE_FRESH_SECS="${AGENT_IDLE_FRESH_SECS:-45}"

agent_state_dir() {
    echo "${TMPDIR:-/tmp}/multiagents-${1:-$SESSION_NAME}"
}

agent_idle_file() {
    echo "$(agent_state_dir "${2:-$SESSION_NAME}")/${1}.idle"
}

# 0 if <role> stamped a heartbeat within AGENT_IDLE_FRESH_SECS.
agent_is_idle() {
    local role="$1" session="${2:-$SESSION_NAME}"
    local hb; hb="$(agent_idle_file "$role" "$session")"
    [[ -f "$hb" ]] || return 1
    local stamp now
    stamp=$(cat "$hb" 2>/dev/null || echo 0)
    [[ "$stamp" =~ ^[0-9]+$ ]] || return 1
    now=$(date +%s)
    (( now - stamp <= AGENT_IDLE_FRESH_SECS ))
}

# Break <role>'s pane out of its idle wait so the message we are about to type
# is read now rather than at the end of the wait window. No-op — deliberately —
# unless the heartbeat proves the pane is only sleeping.
# Usage: agent_wake_pane <pane-id> <role> [session]
agent_wake_pane() {
    local pane="$1" role="$2" session="${3:-$SESSION_NAME}"
    agent_is_idle "$role" "$session" || return 1
    # Escape is claude's interrupt: it ends the blocking Bash call, leaving the
    # session at its prompt, ready to receive the send-keys that follows.
    tmux send-keys -t "$pane" Escape
    sleep 1
    return 0
}
