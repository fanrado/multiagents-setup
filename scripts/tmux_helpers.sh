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

# Stamp a pane with its permanent role.
#
# The pane *title* is not a stable identifier: any program running in the pane
# can rewrite it with an OSC 0/2 escape sequence, and claude does exactly that
# (it advertises the current task). tmux's `allow-set-title` guard only exists
# in tmux >= 3.4, so instead we record the role in a pane-scoped user option,
# which no child process can touch. All pane lookups go through
# tmux_find_pane_by_role; the title is set too, purely for the border label.
tmux_pane_role() {
    local target="$1" role="$2"
    tmux set-option -p -t "$target" @role "$role"
    tmux_pane_title "$target" "$role"
}

# Print the pane ID of the pane holding <role> in <session>, or nothing.
tmux_find_pane_by_role() {
    local session="$1" role="$2"
    tmux list-panes -s -t "$session" -F "#{pane_id} #{@role}" 2>/dev/null \
        | awk -v r="$role" '$2 == r { print $1; exit }'
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
    tmux set-option -t "$session" window-style             "fg=$THEME_FG,bg=$THEME_BG"
    tmux set-option -t "$session" window-active-style      "fg=$THEME_FG,bg=$THEME_BG"
    tmux set-option -t "$session" pane-border-style        "fg=$THEME_BORDER_FG,bg=$THEME_BG"
    tmux set-option -t "$session" pane-active-border-style "fg=$THEME_ACTIVE_FG,bg=$THEME_BG"
    # Label panes from @role (immutable) rather than #{pane_title}, which the
    # program inside the pane can rewrite. @status is an optional transient
    # message set by notify_header.sh.
    tmux set-option -t "$session" pane-border-format \
        " #[bold]#{?@role,#{@role},#{pane_title}}#[nobold]#{?@status, — #{@status},} "

    # Enable mouse (required for the logs pane click binding)
    tmux set-option -t "$session" mouse on
}
