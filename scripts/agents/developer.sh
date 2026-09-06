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

# Idle refresh used to depend on `claude ... "$PROMPT"` exiting after each turn
# so the outer restart loop below could relaunch it and re-check bd ready.
# Claude Code now stays interactive by default (no auto-exit), so that restart
# loop never fires again once a turn ends — the pane would go silent forever
# after finishing a task instead of continuing to poll. Instead, hand the idle
# model one literal, bounded, self-contained loop to run via its own Bash
# tool: scripts/idle_wait.sh blocks and re-polls internally on a real 30s
# cadence (an "every 30 seconds" instruction makes each iteration a whole
# model turn, which is neither 30s nor bounded), and the prompt tells the
# model to just re-run it if it comes back empty, so refreshing no longer
# depends on the wrapper script ever seeing `claude` exit.
#
# While that call blocks, a dispatch typed into this pane only queues. That is
# fine now: idle_wait.sh stamps a heartbeat each iteration and dispatch.sh
# interrupts a provably-sleeping pane before typing, and even a lost keystroke
# is recovered because a dispatched issue stays open in `bd ready`.
POLL_CMD="\"$MULTIAGENTS_ROOT\"/scripts/idle_wait.sh developer $SESSION_NAME"

POLL_PROMPT="No open issues right now. Run this exact command via your Bash tool with a 600000ms timeout and let it run to completion (it blocks itself, re-checking every 30 seconds): $POLL_CMD. If it exits after printing an issue list, read each with 'bd show <id>', claim it with 'bd update <id> --status=in_progress', implement the feature in $WORKSPACE_DIR, commit your changes, then close it with 'bd close <id>', and immediately run 'bd ready' again for more work. If it exits saying the wait window elapsed with nothing found, run the exact same command again right away. Keep repeating — never leave the loop unattended."

WORK_PROMPT="Start your work session: run 'bd ready' to find open issues (skip any titled 'test report'). For each open issue, read it with 'bd show <id>', claim it with 'bd update <id> --status=in_progress', implement the feature in $WORKSPACE_DIR, commit your changes, then close the issue with 'bd close <id>'. After each issue, immediately check 'bd ready' again and continue. Keep going until there is nothing left to do, then run this exact command via your Bash tool with a 600000ms timeout and let it run to completion: $POLL_CMD. If it exits after printing an issue list, go back to implementing. If it exits saying the wait window elapsed with nothing found, run the exact same command again right away."

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
        --add-dir "$MULTIAGENTS_ROOT" \
        --append-system-prompt "$(cat "$INSTRUCTIONS")" \
        "$PROMPT" || true

    echo "[developer] Claude exited. Restarting in 15s..."
    sleep 15
done
