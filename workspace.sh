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
# shellcheck source=scripts/preflight.sh
source "$SCRIPT_DIR/scripts/preflight.sh"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Opens a tmux workspace session with a 2×2 agent grid and a logs button pane.

Layout:
  ┌─────────────────┬─────────────────┐
  │  orchestrator   │   developer     │
  ├─────────────────┼─────────────────┤
  │    tester       │   debugger      │
  ├─────────────────┴─────────────────┤
  │  [ Logs ]  (click to open log)    │
  └───────────────────────────────────┘

Options:
  -s, --session NAME    Session name (default: $SESSION_NAME)
  -d, --dir DIR         Working directory (default: current directory)
  -a, --attach          Attach to existing session if it exists
  -l, --list            List currently running workspace sessions
  -h, --help            Show this help

Keybindings (inside the session):
  C-q               Kill the session and all its panes

Environment variables:
  SESSION_NAME          Override default session name
  WORKSPACE_DIR         Override default working directory
EOF
}

list_workspaces() {
    if ! tmux list-sessions 2>/dev/null | grep -q .; then
        echo "No running workspace sessions."
        return
    fi
    printf "%-20s  %-6s  %-20s  %s\n" "SESSION" "WINDOWS" "CREATED" "ATTACHED"
    tmux list-sessions -F "#{session_name}  #{session_windows}  #{session_created_string}  #{?session_attached,yes,no}" 2>/dev/null \
        | while IFS='  ' read -r name windows created attached; do
            printf "%-20s  %-6s  %-20s  %s\n" "$name" "$windows" "$created" "$attached"
          done
}

attach_only=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--session) SESSION_NAME="$2"; shift 2 ;;
        -d|--dir)     WORKSPACE_DIR="$2"; shift 2 ;;
        -a|--attach)  attach_only=true; shift ;;
        -l|--list)    list_workspaces; exit 0 ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

# Preflight: must be a git repo; beads is optional but agents adapt when absent.
preflight_check_git "$WORKSPACE_DIR" || exit 1
preflight_check_beads || true   # sets NO_BEADS=1, continues

if [[ -z "${NO_BEADS:-}" ]]; then
    issue_count=$(preflight_count_issues "$WORKSPACE_DIR" || echo 0)
    if [[ "$issue_count" -eq 0 ]]; then
        echo "INFO: No open beads issues. Developer will idle until issues are created."
    else
        echo "INFO: $issue_count open issue(s) found."
    fi
fi
export NO_BEADS="${NO_BEADS:-}"

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

# Step 5 — full-width 2-line logs button pane at the very bottom
LOGS_BTN=$(tmux split-window -v -f -l 2 -t "${SESSION_NAME}:${WINDOW_NAME}" \
    -c "$WORKSPACE_DIR" -P -F "#{pane_id}")

# Show pane titles in the border header of each pane
tmux set-option -t "$SESSION_NAME" pane-border-status top

# Label each pane
tmux_pane_title "$TL" "$PANE_ORCHESTRATOR"
tmux_pane_title "$TR" "$PANE_DEVELOPER"
tmux_pane_title "$BL" "$PANE_TESTER"
tmux_pane_title "$BR" "$PANE_DEBUGGER"
tmux_pane_title "$LOGS_BTN" "logs"

# Apply unified color theme
tmux_apply_theme "$SESSION_NAME"

# Store all pane IDs so the resize hook can redistribute space proportionally
tmux set-option -t "$SESSION_NAME" @logs_pane_id "$LOGS_BTN"
tmux set-option -t "$SESSION_NAME" @tl_pane_id   "$TL"
tmux set-option -t "$SESSION_NAME" @tr_pane_id   "$TR"
tmux set-option -t "$SESSION_NAME" @bl_pane_id   "$BL"
tmux set-option -t "$SESSION_NAME" @br_pane_id   "$BR"

# On every terminal resize: evenly distribute the 2×2 grid and keep logs at 2 lines.
tmux set-hook -t "$SESSION_NAME" client-resized \
    "run-shell '$SCRIPT_DIR/scripts/resize_panes.sh #{session_name}'"

# Left-click on the logs pane → open popup; anywhere else → normal pane select
tmux bind-key -T root MouseDown1Pane \
    if-shell -F '#{==:#{pane_id},#{@logs_pane_id}}' \
    "display-popup -E -w 80% -h 70% -T ' Watcher Log ' \
     '$SCRIPT_DIR/scripts/show_watcher_log.sh #{session_name}'" \
    "select-pane -t '#{pane_id}'; send-keys -M"

# Disable mouse border dragging so pane sizes stay fixed
tmux bind-key -T root MouseDrag1Border    ''
tmux bind-key -T root MouseDragEnd1Border ''

# C-q kills the session (no prefix needed)
tmux bind-key -n C-q kill-session

# Launch agents in their respective panes
tmux send-keys -t "$TR" "$SCRIPT_DIR/scripts/agents/developer.sh" Enter
tmux send-keys -t "$BL" "$SCRIPT_DIR/scripts/agents/tester.sh" Enter
tmux send-keys -t "$BR" "$SCRIPT_DIR/scripts/agents/debugger.sh" Enter
tmux send-keys -t "$LOGS_BTN" "$SCRIPT_DIR/scripts/logs_button.sh" Enter

# Start event watcher in background; it exits automatically when session ends.
# Logs: ${TMPDIR:-/tmp}/multiagents-${SESSION_NAME}/watcher.log
SESSION_NAME="$SESSION_NAME" WORKSPACE_DIR="$WORKSPACE_DIR" "$SCRIPT_DIR/scripts/watcher.sh" &
disown

# Start focused on the orchestrator pane
tmux select-pane -t "$TL"

exec tmux attach-session -t "$SESSION_NAME"
