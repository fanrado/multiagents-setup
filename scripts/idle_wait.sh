#!/usr/bin/env bash
# Bounded idle wait for an agent pane — one literal, self-blocking loop.
#
# Usage: idle_wait.sh <role> [session]
#   <role>: developer | tester
#
# Exit 0  — work appeared; the details are printed on stdout.
# Exit 10 — the wait window elapsed with nothing found; the caller re-runs it.
#
# Why this is a script and not prose in the prompt: an idle agent used to be
# told "run <cmd> every 30 seconds", which makes every iteration a whole model
# turn — the real interval is then unbounded and in practice far longer than
# 30s. Only developer.sh had a literal loop. Keeping the loop here gives both
# polling agents the same honest 30s cadence, one place to change the policy,
# and no shell quoting buried in a prompt string.
#
# Each iteration stamps a heartbeat file before sleeping (see scripts/idle.sh),
# so dispatch.sh/msg.sh can tell a pane that is merely waiting — safe to
# interrupt, so a new dispatch is read at once instead of minutes later — from
# a pane doing real work.
set -uo pipefail

ROLE="${1:-}"
if [[ -z "$ROLE" ]]; then
    echo "Usage: idle_wait.sh <role> [session]" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config/workspace.conf
source "$SCRIPT_DIR/../config/workspace.conf"
# shellcheck source=./idle.sh
source "$SCRIPT_DIR/idle.sh"

SESSION="${2:-$SESSION_NAME}"

INTERVAL="${IDLE_INTERVAL:-$AGENT_IDLE_INTERVAL}"
CYCLES="${IDLE_CYCLES:-$AGENT_IDLE_CYCLES}"

bd() { (cd "$WORKSPACE_DIR" && command bd "$@"); }

STATE_DIR="$(agent_state_dir "$SESSION")"
mkdir -p "$STATE_DIR"
HEARTBEAT="$(agent_idle_file "$ROLE" "$SESSION")"

# One probe for work. Prints what it found and returns 0, or returns 1.
probe() {
    case "$ROLE" in
        developer)
            # bd ready lists open, unblocked issues only — a dispatched issue
            # stays open until the developer claims it, so a dispatch whose
            # keystroke was queued or lost is still found here.
            local ready
            ready=$(bd ready --json 2>/dev/null || echo "[]")
            [[ -z "$ready" || "$ready" == "[]" ]] && return 1
            bd ready 2>/dev/null
            ;;
        tester)
            # tester.sh seeds tester-head with the HEAD that predates this
            # session and owns updating it; we only report a divergence.
            local cur last
            cur=$(git -C "$WORKSPACE_DIR" rev-parse HEAD 2>/dev/null || echo "")
            [[ -z "$cur" ]] && return 1
            # No marker (state dir wiped, or the wait started before tester.sh
            # seeded it): adopt HEAD as already-seen rather than reporting it
            # as new, which would have us re-test the same commit every cycle.
            if [[ ! -f "$STATE_DIR/tester-head" ]]; then
                echo "$cur" > "$STATE_DIR/tester-head"
                return 1
            fi
            last=$(cat "$STATE_DIR/tester-head" 2>/dev/null || echo "")
            [[ "$cur" == "$last" ]] && return 1
            echo "New commit to test:"
            git -C "$WORKSPACE_DIR" log -1 --pretty=format:"%s (%h)" 2>/dev/null
            echo
            git -C "$WORKSPACE_DIR" show --stat HEAD 2>/dev/null | head -20
            ;;
        *)
            echo "idle_wait.sh: unknown role '$ROLE'" >&2
            exit 1
            ;;
    esac
    return 0
}

i=0
while [[ $i -lt $CYCLES ]]; do
    if probe; then
        rm -f "$HEARTBEAT"
        exit 0
    fi
    i=$((i + 1))
    # Stamp the heartbeat immediately before sleeping: a sender that sees it
    # fresh knows this pane is parked in `sleep`, not working.
    date +%s > "$HEARTBEAT"
    echo "[$ROLE] Nothing to do. Waiting, refresh in ${INTERVAL}s... ($i/$CYCLES)"
    sleep "$INTERVAL"
done

rm -f "$HEARTBEAT"
echo "[$ROLE] Wait window elapsed ($CYCLES x ${INTERVAL}s) with nothing found — run this command again."
exit 10
