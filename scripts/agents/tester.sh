#!/usr/bin/env bash
# Tester agent — runs Claude in a restart loop so it stays alive between commits.
#
# This agent owns the whole verification half of the pipeline: it writes tests
# for each new commit, runs them, and — since the separate debugger pane was
# removed — diagnoses and fixes the production code itself when they fail,
# rather than filing a report for someone else to pick up.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$WORKSPACE_ROOT/config/workspace.conf"

bd() { (cd "$WORKSPACE_DIR" && command bd "$@"); }

INSTRUCTIONS="$WORKSPACE_ROOT/agents/tester.md"
STATE_DIR="${TMPDIR:-/tmp}/multiagents-${SESSION_NAME}"
HEAD_FILE="$STATE_DIR/tester-head"
LOG_FILE="$STATE_DIR/watcher.log"
mkdir -p "$STATE_DIR"

# Seed with current HEAD so we don't re-test commits that predate this session.
git -C "$WORKSPACE_DIR" rev-parse HEAD 2>/dev/null > "$HEAD_FILE" || echo "" > "$HEAD_FILE"

echo "[tester] WORKSPACE_ROOT : $WORKSPACE_ROOT"
echo "[tester] WORKSPACE_DIR  : $WORKSPACE_DIR"
echo "[tester] git watching   : $WORKSPACE_DIR"
echo "[tester] bd runs from   : $WORKSPACE_DIR"

# Hand the idle model one literal, bounded, blocking loop rather than the prose
# instruction it used to get ("run git log every 30 seconds"). Prose makes each
# iteration a whole model turn, so the real interval is unbounded and in
# practice far longer than 30s; scripts/idle_wait.sh keeps a true 30s cadence,
# and stamps the heartbeat that lets msg.sh interrupt this pane while it sleeps.
POLL_CMD="\"$MULTIAGENTS_ROOT\"/scripts/idle_wait.sh tester $SESSION_NAME"

POLL_PROMPT="No new commits right now. Run this exact command via your Bash tool with a 600000ms timeout and let it run to completion (it blocks itself, re-checking every 30 seconds): $POLL_CMD. If it exits after printing a new commit, write tests for that commit, run them through the shared runner, fix the production code yourself if they fail, and report results via beads — then run the command again. If it exits saying the wait window elapsed with nothing found, run the exact same command again right away. Keep repeating — never leave the loop unattended."

echo "[tester] Starting Claude (restart loop)..."

while true; do
    current_head=$(git -C "$WORKSPACE_DIR" rev-parse HEAD 2>/dev/null || echo "")
    last_head=$(cat "$HEAD_FILE" 2>/dev/null || echo "")

    if [[ -n "$current_head" && "$current_head" != "$last_head" ]]; then
        echo "$current_head" > "$HEAD_FILE"
        short=$(git -C "$WORKSPACE_DIR" log -1 --pretty=format:"%s (%h)" 2>/dev/null || echo "$current_head")
        diff_stat=$(git -C "$WORKSPACE_DIR" show --stat HEAD 2>/dev/null | head -20 || echo "")

        PROMPT="New commit detected: $short

Changed files:
$diff_stat

Write tests for the new feature and run the test suite in $WORKSPACE_DIR. If anything fails, diagnose and fix the production code yourself, then re-run until it passes. Follow your instructions."
        echo "[tester] New commit: $short — starting Claude..."
        work=true
    else
        PROMPT="$POLL_PROMPT"
        echo "[tester] No new commits — Claude will poll and wait"
        work=false
    fi

    # Never pipe claude into `tee`: that hands it a non-TTY stdout, so the
    # interactive session exits immediately instead of waiting for the user,
    # and this loop spins — restarting every 15s and firing a notification
    # each time. Test and fix output already reaches the watcher log through
    # scripts/run_in_watcher.sh; only the session markers are logged here.
    [[ "$work" == true ]] && \
        echo "[tester $(date +%H:%M:%S)] === test run: $short ===" >> "$LOG_FILE"

    claude \
        --dangerously-skip-permissions \
        --add-dir "$WORKSPACE_DIR" \
        --add-dir "$MULTIAGENTS_ROOT" \
        --append-system-prompt "$(cat "$INSTRUCTIONS")" \
        "$PROMPT" || true

    if $work; then
        echo "[tester $(date +%H:%M:%S)] === done ===" >> "$LOG_FILE"
        ts=$(date +%H:%M)
        "$SCRIPT_DIR/../../scripts/notify_header.sh" "$SESSION_NAME" \
            "[tester] Tests done: $short ($ts)" 2>/dev/null || true
    fi

    echo "[tester] Claude exited. Restarting in 15s..."
    sleep 15
done
