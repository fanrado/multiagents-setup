#!/usr/bin/env bash
# Opened by the [ Logs ] pane click via tmux display-popup.
# Usage: show_watcher_log.sh <session-name>
SESSION="${1:-multiagents}"
LOG_FILE="${TMPDIR:-/tmp}/multiagents-${SESSION}/watcher.log"

if [[ -f "$LOG_FILE" ]]; then
    less +G "$LOG_FILE"
else
    echo "(no log yet — watcher has not started)"
    printf '\n[press enter to close] '
    read -r _
fi
