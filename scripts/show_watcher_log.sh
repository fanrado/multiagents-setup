#!/usr/bin/env bash
# Opened by the [ Logs ] status-bar button via tmux display-popup.
# Usage: show_watcher_log.sh <session-name>
SESSION="${1:-multiagents}"
LOG_FILE="${TMPDIR:-/tmp}/multiagents-${SESSION}/watcher.log"

if [[ -f "$LOG_FILE" ]]; then
    tail -n 150 "$LOG_FILE"
else
    echo "(no log yet — watcher has not started)"
fi

printf '\n[press enter to close] '
read -r _
