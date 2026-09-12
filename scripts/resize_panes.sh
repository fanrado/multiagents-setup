#!/usr/bin/env bash
# Resize the 3-pane agent layout to fill the terminal after a window resize.
# Called from the tmux client-resized hook with the session name as $1.
#
# Layout: orchestrator occupies the full-height left column; developer (top)
# and tester (bottom) share the right column; a 2-line logs button spans the
# full width underneath.
set -euo pipefail

SESSION="$1"

logs_pane=$(tmux show-option -qv -t "$SESSION" @logs_pane_id)
left_pane=$(tmux show-option -qv -t "$SESSION" @left_pane_id)
tr_pane=$(tmux show-option  -qv -t "$SESSION" @tr_pane_id)
br_pane=$(tmux show-option  -qv -t "$SESSION" @br_pane_id)

[[ -z "$logs_pane" || -z "$left_pane" || -z "$tr_pane" || -z "$br_pane" ]] && exit 0

# Current window dimensions
win_h=$(tmux display-message -t "${SESSION}" -p "#{window_height}")
win_w=$(tmux display-message -t "${SESSION}" -p "#{window_width}")

logs_h=2
grid_h=$(( win_h - logs_h - 1 ))   # -1 for the border above the logs pane
[[ $grid_h -lt 4 ]] && exit 0

left_w=$(( win_w / 2 ))
top_h=$(( grid_h / 2 ))

# Three resizes are enough, and the order matters. The left column spans the
# whole grid height by construction (it is never split vertically), so only its
# width is set here; sizing the right column's top pane then leaves the rest of
# the height to the bottom pane.
tmux resize-pane -t "$logs_pane" -y "$logs_h"
tmux resize-pane -t "$left_pane" -x "$left_w"
tmux resize-pane -t "$tr_pane"   -y "$top_h"
