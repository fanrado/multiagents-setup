#!/usr/bin/env bash
# Runner — persistent shell that executes commands submitted via a FIFO, so
# they run as a real, live process (not something buried inside an
# individual agent's own Bash-tool sandbox) and stream into the shared
# Watcher Log as they happen. Lives in its own tmux window ("runner"),
# separate from the visible 2x2 agent grid, so a human can also switch to
# it and watch commands execute like a normal terminal.
#
# See scripts/run_in_watcher.sh for how agents submit commands, and
# agents/tester.md / agents/debugger.md for when they should.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$WORKSPACE_ROOT/config/workspace.conf"

STATE_DIR="${TMPDIR:-/tmp}/multiagents-${SESSION_NAME}"
FIFO="$STATE_DIR/runner.fifo"
LOG_FILE="$STATE_DIR/watcher.log"
mkdir -p "$STATE_DIR"
[[ -p "$FIFO" ]] || mkfifo "$FIFO"

cd "$WORKSPACE_DIR" 2>/dev/null || true

echo "[runner] Ready in $WORKSPACE_DIR"
echo "[runner] Commands submitted via scripts/run_in_watcher.sh execute here"
echo "[runner] and stream to $LOG_FILE"

# Keep the FIFO open read-write on our own fd for the life of this process.
# This is the standard idiom for a FIFO-backed work queue: without it, the
# `read` loop sees EOF and exits every time a writer closes its end between
# separate submissions, instead of blocking for the next one.
exec 3<> "$FIFO"

while IFS= read -r line <&3; do
    [[ -z "$line" ]] && continue
    {
        echo "[runner $(date +%H:%M:%S)] \$ $line"
        eval "$line"
    } 2>&1 | tee -a "$LOG_FILE"
done
