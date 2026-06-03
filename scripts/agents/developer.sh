#!/usr/bin/env bash
# Developer agent — runs Claude in a restart loop so it stays alive between issues.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$WORKSPACE_ROOT/config/workspace.conf"
source "$WORKSPACE_ROOT/scripts/preflight.sh"

bd() { (cd "$WORKSPACE_DIR" && command bd "$@"); }

INSTRUCTIONS="$WORKSPACE_ROOT/agents/developer.md"

echo "[developer] WORKSPACE_ROOT : $WORKSPACE_ROOT"
echo "[developer] WORKSPACE_DIR  : $WORKSPACE_DIR"

POLL_PROMPT="No open issues right now. Run 'bd ready' every 30 seconds. As soon as an issue appears, read it with 'bd show <id>', implement the feature in $WORKSPACE_DIR, commit your changes, then close it with 'bd close <id>'. Keep looping."

WORK_PROMPT="Start your work session: run 'bd ready' to find open issues (skip any titled 'test report'). For each open issue, read it with 'bd show <id>', implement the feature in $WORKSPACE_DIR, commit your changes, then close the issue with 'bd close <id>'. After each issue, immediately check 'bd ready' again and continue. Keep going until there is nothing left to do, then run 'bd ready' every 30 seconds and wait."

NO_BEADS_PROMPT="No beads issue tracker is available. Explore $WORKSPACE_DIR, understand the codebase, and wait for direct instructions."

echo "[developer] Starting Claude (restart loop)..."

while true; do
    if [[ -n "${NO_BEADS:-}" ]]; then
        PROMPT="$NO_BEADS_PROMPT"
        echo "[developer] No beads — starting in no-tracking mode"
    else
        open_count=$(preflight_count_issues "$WORKSPACE_DIR" || echo 0)
        if [[ "$open_count" -gt 0 ]]; then
            PROMPT="$WORK_PROMPT"
            echo "[developer] $open_count open issue(s) — starting work"
        else
            PROMPT="$POLL_PROMPT"
            echo "[developer] No open issues — Claude will poll and wait"
        fi
    fi

    claude \
        --dangerously-skip-permissions \
        --add-dir "$WORKSPACE_DIR" \
        --append-system-prompt "$(cat "$INSTRUCTIONS")" \
        "$PROMPT" || true

    echo "[developer] Claude exited. Restarting in 15s..."
    sleep 15
done
