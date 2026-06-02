#!/usr/bin/env bash
# Preflight checks sourced by workspace.sh and agent scripts.
# Each function prints a message to stderr and returns a non-zero exit code on failure.
# Sets NO_BEADS=1 in the caller's environment when bd is unavailable.

preflight_check_git() {
    local dir="${1:?preflight_check_git requires a directory}"
    if ! git -C "$dir" rev-parse --git-dir > /dev/null 2>&1; then
        echo "ERROR: '$dir' is not a git repository. Nothing to do." >&2
        return 1
    fi
}

preflight_check_beads() {
    if ! command -v bd > /dev/null 2>&1; then
        echo "WARNING: 'bd' not found on PATH. Agents will start without beads tracking." >&2
        export NO_BEADS=1
        return 1
    fi
}

# Prints the count of open issues to stdout. Returns 1 if none found.
preflight_count_issues() {
    local dir="${1:?preflight_count_issues requires a directory}"
    local count
    count=$(bd list --status=open 2>/dev/null | grep -c '.' || echo 0)
    echo "$count"
    [[ "$count" -gt 0 ]]
}
