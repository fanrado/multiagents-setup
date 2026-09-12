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
# shellcheck source=scripts/conda_env.sh
source "$SCRIPT_DIR/scripts/conda_env.sh"

# Put the conda-installed tmux (see setup.sh) on PATH, if that env exists.
activate_tools_env

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Opens a tmux workspace session with 3 agent panes.

Layout:
  ┌─────────────────┬─────────────────┐
  │                 │   developer     │
  │  orchestrator   ├─────────────────┤
  │                 │    tester       │
  └─────────────────┴─────────────────┘

Plus a hidden "runner" window (not shown above, switch with C-b w): a
persistent shell that test/build commands run in via scripts/run_in_watcher.sh.
Their output streams live into the watcher log, which you read with:
  tail -f \${TMPDIR:-/tmp}/multiagents-<session>/watcher.log

Options:
  -s, --session NAME    Session name (default: $SESSION_NAME)
  -d, --dir DIR         Working directory (default: current directory)
  -a, --attach          Attach to existing session if it exists
  -l, --list            List currently running workspace sessions
  -h, --help            Show this help

Keybindings (inside the session):
  C-q               Stop all agent processes and the watcher, then kill the session

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

# Step 1 — create session; capture the first pane ID (the full-height left column)
tmux new-session -d -s "$SESSION_NAME" -n "$WINDOW_NAME" -c "$WORKSPACE_DIR"
LEFT=$(tmux_pane_id "${SESSION_NAME}:${WINDOW_NAME}")   # left, full height

# Step 2 — split the left column rightward → right column
TR=$(tmux_split_h "$LEFT" "$WORKSPACE_DIR")            # top-right

# Step 3 — split the right column downward. Only the right column is split
# vertically, which is what keeps the orchestrator at the full height of the
# window: a 3-pane layout rather than a 2×2 grid.
BR=$(tmux_split_v "$TR" "$WORKSPACE_DIR")              # bottom-right

# Show pane titles in the border header of each pane
tmux set-option -t "$SESSION_NAME" pane-border-status top

# Label each pane and stamp its permanent role. Scripts look panes up by
# @role, never by title: claude rewrites the pane title with the task it is
# working on, which used to make dispatch.sh & co. lose the developer pane.
tmux_pane_role "$LEFT" "$PANE_ORCHESTRATOR"
tmux_pane_role "$TR" "$PANE_DEVELOPER"
tmux_pane_role "$BR" "$PANE_TESTER"


# Apply unified color theme
tmux_apply_theme "$SESSION_NAME"

# Store all pane IDs so the resize hook can redistribute space proportionally
tmux set-option -t "$SESSION_NAME" @left_pane_id "$LEFT"
tmux set-option -t "$SESSION_NAME" @tr_pane_id   "$TR"
tmux set-option -t "$SESSION_NAME" @br_pane_id   "$BR"

# On every terminal resize: split the width evenly between the orchestrator
# column and the stacked right column.
tmux set-hook -t "$SESSION_NAME" client-resized \
    "run-shell '$SCRIPT_DIR/scripts/resize_panes.sh #{session_name}'"

# Step 4 — hidden "runner" window: a persistent shell that executes commands
# submitted via scripts/run_in_watcher.sh, so the tester's test and build runs
# are real live processes streaming into the watcher log, not something buried
# inside an individual agent's own Bash-tool sandbox. Not part of the visible
# 3-pane layout; switch to it with tmux's window list (C-b w) to watch it.
tmux new-window -d -n runner -t "$SESSION_NAME" -c "$WORKSPACE_DIR"
tmux_pane_role "$(tmux_pane_id "${SESSION_NAME}:runner")" "runner"

# Belt and braces: freeze the names the panes and windows already have.
# allow-set-title (tmux >= 3.4) blocks OSC 0/2 pane-title rewrites outright;
# allow-rename blocks OSC window renames. Both are silently skipped on older
# tmux, where the @role lookups above are what actually guarantee correctness.
for _w in $(tmux list-windows -t "$SESSION_NAME" -F "#{window_id}"); do
    tmux set-option -w -t "$_w" allow-set-title off 2>/dev/null || true
    tmux set-option -w -t "$_w" allow-rename off 2>/dev/null || true
    tmux set-option -w -t "$_w" automatic-rename off 2>/dev/null || true
done
unset _w

# Restore tmux's default left-click behaviour explicitly: select the pane and
# forward the click, which is what all three agent panes want.
#
# This is a reset, not a no-op. Key bindings live on the tmux *server*, not on
# the session, and a server outlives any one workspace — so a server that ever
# ran an older workspace.sh still carries its MouseDown1Pane override, which
# turned a bottom [ Logs ] pane into a button opening a popup via a script this
# repo no longer ships. Simply dropping the bind-key here would leave that
# stale binding in place for every existing user until they killed their
# server. Binding the default back makes the outcome the same either way.
#
# The command list is one quoted argument. Written unquoted, the `;` would end
# the bind-key command itself, binding only `select-pane` and running
# `send-keys -M` as a stray command — which silently drops the click-through
# half of the default, so a click would select a pane but never reach the
# program inside it.
tmux bind-key -T root MouseDown1Pane "select-pane -t = ; send-keys -M"

# Disable mouse border dragging so pane sizes stay fixed
tmux bind-key -T root MouseDrag1Border    ''
tmux bind-key -T root MouseDragEnd1Border ''

# C-q kills the session (no prefix needed) — routed through quit_workspace.sh
# so every pane's restart loop and claude child is actually stopped, not just
# detached, and the watcher is stopped explicitly instead of waiting out its
# poll interval.
tmux bind-key -n C-q run-shell "$SCRIPT_DIR/scripts/quit_workspace.sh #{session_name}"

# Launch agents in their respective panes
tmux send-keys -t "$LEFT" "$SCRIPT_DIR/scripts/agents/orchestrator.sh" Enter
tmux send-keys -t "$TR" "$SCRIPT_DIR/scripts/agents/developer.sh" Enter
tmux send-keys -t "$BR" "$SCRIPT_DIR/scripts/agents/tester.sh" Enter
tmux send-keys -t "${SESSION_NAME}:runner" "$SCRIPT_DIR/scripts/agents/runner.sh" Enter

# Start event watcher in background; it exits automatically when session ends.
# Logs: ${TMPDIR:-/tmp}/multiagents-${SESSION_NAME}/watcher.log
SESSION_NAME="$SESSION_NAME" WORKSPACE_DIR="$WORKSPACE_DIR" "$SCRIPT_DIR/scripts/watcher.sh" &
disown

# Start focused on the orchestrator pane
tmux select-pane -t "$LEFT"

exec tmux attach-session -t "$SESSION_NAME"
