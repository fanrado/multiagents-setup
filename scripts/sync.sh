#!/usr/bin/env bash
# Sync between feature and test branches.
#
# Usage:
#   sync.sh to-test    <feature-name>   # rebase test/<name> onto features/<name>
#   sync.sh to-feature <feature-name>   # rebase features/<name> onto test/<name>
set -euo pipefail

COMMAND="${1:?Usage: sync.sh <to-test|to-feature> <feature-name>}"
FEATURE_NAME="${2:?Usage: sync.sh <to-test|to-feature> <feature-name>}"

FEATURE_BRANCH="features/${FEATURE_NAME}"
TEST_BRANCH="test/${FEATURE_NAME}"

current_branch() {
    git rev-parse --abbrev-ref HEAD
}

require_clean_tree() {
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "sync.sh: working tree is not clean. Commit or stash changes first." >&2
        exit 1
    fi
}

case "$COMMAND" in
    to-test)
        echo "Syncing $FEATURE_BRANCH → $TEST_BRANCH"
        require_clean_tree
        ORIG=$(current_branch)
        git checkout "$TEST_BRANCH"
        git rebase "$FEATURE_BRANCH"
        git checkout "$ORIG"
        echo "Done. $TEST_BRANCH is now up to date with $FEATURE_BRANCH."
        ;;

    to-feature)
        echo "Syncing $TEST_BRANCH → $FEATURE_BRANCH"
        require_clean_tree
        ORIG=$(current_branch)
        git checkout "$FEATURE_BRANCH"
        git rebase "$TEST_BRANCH"
        git checkout "$ORIG"
        echo "Done. $FEATURE_BRANCH is now up to date with $TEST_BRANCH."
        ;;

    *)
        echo "sync.sh: unknown command '$COMMAND'. Use 'to-test' or 'to-feature'." >&2
        exit 1
        ;;
esac
