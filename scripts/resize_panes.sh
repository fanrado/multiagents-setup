#!/usr/bin/env bash
# Resize the 2x2 agent grid to fill the terminal after a window resize.
# Called from the tmux client-resized hook with the session name as $1.
set -euo pipefail

SESSION="$1"

logs_pane=$(tmux show-option -qv -t "$SESSION" @logs_pane_id)
tl_pane=$(tmux show-option   -qv -t "$SESSION" @tl_pane_id)
tr_pane=$(tmux show-option   -qv -t "$SESSION" @tr_pane_id)
bl_pane=$(tmux show-option   -qv -t "$SESSION" @bl_pane_id)
br_pane=$(tmux show-option   -qv -t "$SESSION" @br_pane_id)

[[ -z "$logs_pane" || -z "$tl_pane" ]] && exit 0

# Current window dimensions
win_h=$(tmux display-message -t "${SESSION}" -p "#{window_height}")
win_w=$(tmux display-message -t "${SESSION}" -p "#{window_width}")

logs_h=2
# pane-border-status top adds 1 border row per pane row; 2 rows × 1 border = 2 rows
# layout: [border+TL | border+BL | border+logs] in height
# tmux accounts for borders internally; just split remaining height evenly
grid_h=$(( win_h - logs_h - 1 ))   # -1 for the border above the logs pane
[[ $grid_h -lt 4 ]] && exit 0

top_h=$(( grid_h / 2 ))
bot_h=$(( grid_h - top_h ))
left_w=$(( win_w / 2 ))
right_w=$(( win_w - left_w ))

tmux resize-pane -t "$logs_pane" -y "$logs_h"
tmux resize-pane -t "$tl_pane"   -x "$left_w"  -y "$top_h"
tmux resize-pane -t "$tr_pane"   -x "$right_w" -y "$top_h"
tmux resize-pane -t "$bl_pane"   -x "$left_w"  -y "$bot_h"
tmux resize-pane -t "$br_pane"   -x "$right_w" -y "$bot_h"
