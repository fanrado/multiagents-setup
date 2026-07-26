#!/usr/bin/env bash
# Opened by the [ Logs ] pane click via tmux display-popup.
# Usage: show_watcher_log.sh <session-name>
SESSION="${1:-multiagents}"
LOG_FILE="${TMPDIR:-/tmp}/multiagents-${SESSION}/watcher.log"

if [[ -f "$LOG_FILE" ]]; then
    # +F: follow mode, like `tail -f`, so new output (e.g. a test run
    # streaming through scripts/run_in_watcher.sh) appears live. Ctrl-C
    # drops out of follow mode into normal scrollback, `F` resumes it.
    less +F "$LOG_FILE"
else
    echo "(no log yet — watcher has not started)"
    printf '\n[press enter to close] '
    read -r _
fi
