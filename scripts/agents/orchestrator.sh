#!/usr/bin/env bash
# Orchestrator agent — runs Claude in a restart loop, same pattern as
# developer/tester/debugger, so the planning instructions are always loaded
# whenever a Claude session starts in this pane (including after a manual
# /exit or a crash). This pane is interactive and human-present, so each run
# is foreground with normal permission prompts (no --dangerously-skip-permissions).
#
# Never pass --continue/--resume here: this loop intentionally always starts
# a fresh conversation. Reattaching to a previous workspace is handled by
# `workspace --attach` (tmux session persistence), not Claude's own resume
# feature — see scripts/quit_workspace.sh, which fully stops this loop (and
# the claude child) when the workspace is quit, so there is never orphaned
# session state to resume from.
#
# --disallowed-tools hard-blocks file mutation at the tool level (verified
# against `claude --help`) — this holds regardless of permission mode, unlike
# the "never write code" rule in orchestrator.md, which is a written
# instruction the model could in principle ignore. The orchestrator plans;
# it never edits.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$WORKSPACE_ROOT/config/workspace.conf"

INSTRUCTIONS="$WORKSPACE_ROOT/agents/orchestrator.md"

echo "[orchestrator] WORKSPACE_ROOT : $WORKSPACE_ROOT"
echo "[orchestrator] WORKSPACE_DIR  : $WORKSPACE_DIR"
echo "[orchestrator] Starting Claude (restart loop)..."

while true; do
    claude \
        --add-dir "$WORKSPACE_DIR" \
        --disallowed-tools "Edit,Write,NotebookEdit" \
        --append-system-prompt "$(cat "$INSTRUCTIONS")" || true

    echo "[orchestrator] Claude exited. Restarting in 2s..."
    sleep 2
done
