#!/usr/bin/env bash
set -euo pipefail

# Capture the directory from which the user invoked this script.
# This becomes the project workspace; -d/--dir can still override it.
WORKSPACE_DIR="$(pwd)"

# Resolve the real location of this script so that symlinks (e.g. ~/bin/workspace)
# still find config/ and scripts/ relative to the actual multiagents-setup directory.
_src="${BASH_SOURCE[0]}"
while [[ -L "$_src" ]]; do
    _dir="$(cd "$(dirname "$_src")" && pwd)"
    _src="$(readlink "$_src")"
    [[ "$_src" != /* ]] && _src="$_dir/$_src"
done
SCRIPT_DIR="$(cd "$(dirname "$_src")" && pwd)"
unset _src _dir

# shellcheck source=config/workspace.conf
source "$SCRIPT_DIR/config/workspace.conf"
# shellcheck source=scripts/tmux_helpers.sh
source "$SCRIPT_DIR/scripts/tmux_helpers.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Opens a tmux workspace session with 4 panes in a 2×2 grid.

Layout:
  ┌─────────────────┬─────────────────┐
  │  orchestrator   │   developer     │
  ├─────────────────┼─────────────────┤
  │    tester       │   debugger      │
  └─────────────────┴─────────────────┘

Options:
  -s, --session NAME    Session name (default: $SESSION_NAME)
  -d, --dir DIR         Working directory (default: current directory)
  -a, --attach          Attach to existing session if it exists
  -h, --help            Show this help

Keybindings (inside the session):
  C-q               Kill the session and all its panes

Environment variables:
  SESSION_NAME          Override default session name
  WORKSPACE_DIR         Override default working directory
EOF
}

attach_only=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--session) SESSION_NAME="$2"; shift 2 ;;
        -d|--dir)     WORKSPACE_DIR="$2"; shift 2 ;;
        -a|--attach)  attach_only=true; shift ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if tmux_session_exists "$SESSION_NAME"; then
    if $attach_only; then
        exec tmux attach-session -t "$SESSION_NAME"
    fi
    echo "Session '$SESSION_NAME' already exists. Use --attach to connect or choose a different name." >&2
    exit 1
fi

echo "Starting workspace: $SESSION_NAME"
echo "Working directory:  $WORKSPACE_DIR"

# Step 1 — create session; capture the first pane ID (top-left)
tmux new-session -d -s "$SESSION_NAME" -n "$WINDOW_NAME" -c "$WORKSPACE_DIR"
TL=$(tmux_pane_id "${SESSION_NAME}:${WINDOW_NAME}")   # top-left

# Step 2 — split top-left rightward → top-right
TR=$(tmux_split_h "$TL" "$WORKSPACE_DIR")             # top-right

# Step 3 — split top-left downward → bottom-left
BL=$(tmux_split_v "$TL" "$WORKSPACE_DIR")             # bottom-left

# Step 4 — split top-right downward → bottom-right
BR=$(tmux_split_v "$TR" "$WORKSPACE_DIR")             # bottom-right

# Label each pane
tmux_pane_title "$TL" "$PANE_ORCHESTRATOR"
tmux_pane_title "$TR" "$PANE_DEVELOPER"
tmux_pane_title "$BL" "$PANE_TESTER"
tmux_pane_title "$BR" "$PANE_DEBUGGER"

# C-q kills the session (no prefix needed)
tmux bind-key -n C-q kill-session

# Launch agents in their respective panes
tmux send-keys -t "$TR" "$SCRIPT_DIR/scripts/agents/developer.sh" Enter
tmux send-keys -t "$BL" "$SCRIPT_DIR/scripts/agents/tester.sh" Enter
tmux send-keys -t "$BR" "$SCRIPT_DIR/scripts/agents/debugger.sh" Enter

# Start event watcher in background; it exits automatically when session ends.
# Logs: ${TMPDIR:-/tmp}/multiagents-${SESSION_NAME}/watcher.log
SESSION_NAME="$SESSION_NAME" WORKSPACE_DIR="$WORKSPACE_DIR" "$SCRIPT_DIR/scripts/watcher.sh" &
disown

# Start focused on the orchestrator pane
tmux select-pane -t "$TL"

exec tmux attach-session -t "$SESSION_NAME"
