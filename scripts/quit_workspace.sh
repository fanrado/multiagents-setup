#!/usr/bin/env bash
# Forcefully stop every agent process and the watcher before tearing down the
# tmux session, so nothing lingers after C-q. This matters because the
# developer/tester/debugger/orchestrator panes all run `claude` inside a
# `while true` restart loop: a plain `tmux kill-session` relies on the kernel
# delivering SIGHUP to each pane's foreground process group, which is not
# guaranteed to reach every descendant. We never pass --continue/--resume in
# any launch script, so there is no Claude-side session to resume anyway —
# but a lingering process would still show up as a zombie/duplicate agent.
# Reattaching to a workspace is `workspace --attach` (tmux session
# persistence), not something a leftover claude process should offer.
#
# Usage: quit_workspace.sh <session-name>
set -uo pipefail

SESSION_NAME="${1:?Usage: quit_workspace.sh <session-name>}"

# Snapshot pane PIDs before killing anything — panes disappear from
# `tmux list-panes` as soon as their process exits, so a second query later
# would miss survivors we still need to force-kill.
# (Built with a while-read loop, not `mapfile`, since macOS ships bash 3.2
# where `mapfile`/`readarray` don't exist.)
PANE_PIDS=()
while IFS= read -r pid; do
    [[ -n "$pid" ]] && PANE_PIDS+=("$pid")
done < <(tmux list-panes -t "$SESSION_NAME" -F "#{pane_pid}" 2>/dev/null)

STATE_DIR="${TMPDIR:-/tmp}/multiagents-${SESSION_NAME}"
WATCHER_PID=""
[[ -f "$STATE_DIR/watcher.pid" ]] && WATCHER_PID="$(cat "$STATE_DIR/watcher.pid" 2>/dev/null)"

pgid_of() { ps -o pgid= "$1" 2>/dev/null | tr -d ' '; }

# "${PANE_PIDS[@]}" errors under `set -u` on an empty array in bash < 4.4
# (macOS ships 3.2) — the ${arr[@]+"${arr[@]}"} guard avoids that.

# First pass: ask nicely (SIGTERM) so hooks/cleanup can run.
for pid in ${PANE_PIDS[@]+"${PANE_PIDS[@]}"}; do
    [[ -z "$pid" ]] && continue
    pgid="$(pgid_of "$pid")"
    [[ -n "$pgid" ]] && kill -TERM -- "-$pgid" 2>/dev/null
done
[[ -n "$WATCHER_PID" ]] && kill -TERM "$WATCHER_PID" 2>/dev/null

sleep 0.5

# Second pass: force-kill anything still alive.
for pid in ${PANE_PIDS[@]+"${PANE_PIDS[@]}"}; do
    [[ -z "$pid" ]] && continue
    pgid="$(pgid_of "$pid")"
    [[ -n "$pgid" ]] && kill -KILL -- "-$pgid" 2>/dev/null
done
[[ -n "$WATCHER_PID" ]] && kill -KILL "$WATCHER_PID" 2>/dev/null

tmux kill-session -t "$SESSION_NAME" 2>/dev/null
exit 0
