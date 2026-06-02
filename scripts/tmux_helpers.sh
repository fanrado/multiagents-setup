#!/usr/bin/env bash
# Tmux utility functions shared across workspace scripts

tmux_session_exists() {
    tmux has-session -t "$1" 2>/dev/null
}

# Return the pane ID of the first pane in a window
tmux_pane_id() {
    tmux display-message -t "$1" -p "#{pane_id}"
}

# Split a pane left/right (like C-b |). Prints the new pane's ID.
tmux_split_h() {
    local target="$1" dir="$2"
    tmux split-window -h -t "$target" -c "$dir" -P -F "#{pane_id}"
}

# Split a pane top/bottom (like C-b -). Prints the new pane's ID.
tmux_split_v() {
    local target="$1" dir="$2"
    tmux split-window -v -t "$target" -c "$dir" -P -F "#{pane_id}"
}

# Set the visible title of a pane (requires tmux >= 2.6)
tmux_pane_title() {
    local target="$1" title="$2"
    tmux select-pane -t "$target" -T "$title"
}

tmux_send() {
    local target="$1"
    shift
    tmux send-keys -t "$target" "$*" Enter
}

# Apply unified color theme to a session.
# Usage: tmux_apply_theme <session>
tmux_apply_theme() {
    local session="$1"

    # Unified pane backgrounds and borders
    tmux set-option -t "$session" window-style             "bg=$THEME_BG"
    tmux set-option -t "$session" window-active-style      "bg=$THEME_BG"
    tmux set-option -t "$session" pane-border-style        "fg=$THEME_BORDER_FG,bg=$THEME_BG"
    tmux set-option -t "$session" pane-active-border-style "fg=$THEME_ACTIVE_FG,bg=$THEME_BG"
    tmux set-option -t "$session" pane-border-format       " #[bold]#{pane_title}#[nobold] "

    # Enable mouse (required for the logs pane click binding)
    tmux set-option -t "$session" mouse on
}
