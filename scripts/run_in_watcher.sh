#!/usr/bin/env bash
# Submit a command to the shared runner terminal (scripts/agents/runner.sh)
# instead of running it directly in the caller's own Bash tool. The command
# executes as a real process in the runner's window and its output streams
# live into the Watcher Log (watcher.log / the [Logs] popup) as it happens.
# Blocks until the command finishes, relays its output to our own stdout as
# it arrives (so the calling agent sees it too), and exits with the same
# exit code the command itself produced.
#
# Usage: run_in_watcher.sh <session> <command...>
# Example: run_in_watcher.sh multiagents "npm test"
set -uo pipefail

SESSION="${1:?Usage: run_in_watcher.sh <session> <command...>}"
shift
CMD="$*"
if [[ -z "$CMD" ]]; then
    echo "run_in_watcher.sh: no command given" >&2
    exit 1
fi

STATE_DIR="${TMPDIR:-/tmp}/multiagents-${SESSION}"
FIFO="$STATE_DIR/runner.fifo"
LOG_FILE="$STATE_DIR/watcher.log"

if [[ ! -p "$FIFO" ]]; then
    echo "run_in_watcher.sh: runner not available (no FIFO at $FIFO)." >&2
    echo "Is the workspace running? The runner window starts with it." >&2
    exit 1
fi

TOKEN="RUNNER_DONE_$$_$RANDOM"
start_line=0
[[ -f "$LOG_FILE" ]] && start_line=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
# Ensure the file exists before `tail -f` below: BSD tail (macOS default),
# unlike GNU tail, doesn't wait/retry for a missing file — it just errors
# out immediately, silently losing the live relay on the very first command.
touch "$LOG_FILE"

# Build ONE line combining the command and its own exit-code report, so the
# runner evaluates both in a single shell invocation — $? must be captured
# right after the command, not in a separate FIFO line/loop iteration, or it
# would reflect the runner loop's own bookkeeping instead. The command runs
# in a subshell `( ... )`, not a brace group `{ ... }`: if CMD itself calls
# `exit` (common in test runners), a brace group would exit the *runner
# process*, permanently killing it — a subshell contains that to just the
# submitted command.
FULL_LINE="( ${CMD} ); printf '${TOKEN}:%s\n' \"\$?\""
printf '%s\n' "$FULL_LINE" > "$FIFO"

# Follow new log output live so the caller sees it as it happens, until the
# completion token shows up.
tail -n +"$((start_line + 1))" -f "$LOG_FILE" &
TAIL_PID=$!

# Bounded wait, not an indefinite one: if the runner dies mid-command for any
# reason, the token never arrives and this would otherwise hang forever.
# Override with RUN_IN_WATCHER_TIMEOUT (seconds) for longer-running suites.
TIMEOUT="${RUN_IN_WATCHER_TIMEOUT:-1800}"
waited=0
while ! grep -q "^${TOKEN}:" "$LOG_FILE" 2>/dev/null; do
    sleep 0.5
    waited=$((waited + 1))
    if [[ $((waited / 2)) -ge "$TIMEOUT" ]]; then
        kill "$TAIL_PID" 2>/dev/null
        wait "$TAIL_PID" 2>/dev/null
        echo "run_in_watcher.sh: timed out after ${TIMEOUT}s waiting for the runner (is it still alive?)" >&2
        exit 124
    fi
done

kill "$TAIL_PID" 2>/dev/null
wait "$TAIL_PID" 2>/dev/null

exit_code=$(grep "^${TOKEN}:" "$LOG_FILE" | tail -1 | cut -d: -f2)
exit "${exit_code:-1}"
