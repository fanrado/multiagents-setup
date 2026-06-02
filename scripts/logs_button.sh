#!/usr/bin/env bash
# Runs in the logs-button pane. Displays a styled [ Logs ] button.
# Mouse clicks on this pane are handled by the MouseDown1Pane binding in workspace.sh.
printf '\033[1;34;7m [ Logs ] \033[0m  click to open watcher log'
while true; do sleep 3600; done
