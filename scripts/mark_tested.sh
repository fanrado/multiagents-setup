#!/usr/bin/env bash
# Stamp the current HEAD as already tested, so the tester's idle poll does not
# surface it as new work.
#
# Why this exists: the tester now fixes the production code when its own tests
# fail (the debugger role was folded into it), and those fixes are commits. The
# tester's trigger is "HEAD moved", so without this the tester would wake up on
# its own fix commit and re-test the thing it just verified — a loop that only
# ends because the fix eventually stops changing anything. Calling this right
# after committing a fix closes that loop explicitly.
#
# Usage: mark_tested.sh [session-name]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../config/workspace.conf
source "$SCRIPT_DIR/../config/workspace.conf"
# shellcheck source=./idle.sh
source "$SCRIPT_DIR/idle.sh"

SESSION="${1:-$SESSION_NAME}"

STATE_DIR="$(agent_state_dir "$SESSION")"
mkdir -p "$STATE_DIR"

head=$(git -C "$WORKSPACE_DIR" rev-parse HEAD 2>/dev/null || echo "")
if [[ -z "$head" ]]; then
    echo "mark_tested.sh: no git HEAD in $WORKSPACE_DIR" >&2
    exit 1
fi

echo "$head" > "$STATE_DIR/tester-head"
echo "mark_tested.sh: HEAD $(git -C "$WORKSPACE_DIR" log -1 --pretty=format:'%h %s') marked as tested."
