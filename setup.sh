#!/usr/bin/env bash
# setup.sh — prepare a machine to run the multiagents workspace.
#
# Checks for the tools workspace.sh depends on and installs the missing ones:
#   - tmux  (>= 2.6, needed for pane titles)            -> system package manager
#   - bd    (beads issue tracker)                        -> official installer / brew / npm / go
#   - claude (Claude Code CLI)                           -> checked only, never installed
#   - git, bash >= 4                                     -> checked only
#
# Usage: ./setup.sh [--check] [--dry-run] [--yes] [-h]
set -euo pipefail

TMUX_MIN_VERSION="2.6"
BEADS_INSTALL_URL="https://raw.githubusercontent.com/gastownhall/beads/main/scripts/install.sh"

CHECK_ONLY=0
DRY_RUN=0
ASSUME_YES=0

usage() {
    cat <<USAGE
Usage: $(basename "$0") [OPTIONS]

Checks that tmux and bd (beads) are installed and installs them if missing.
Also reports on git, bash and the claude CLI, which are required but not
installed by this script.

Options:
  --check      Only report what is installed/missing; never install (exit 1 if
               anything required is missing).
  --dry-run    Print the install commands that would run, without running them.
  -y, --yes    Do not prompt before installing.
  -h, --help   Show this help.

Environment:
  BEADS_INSTALL_METHOD   Force one of: script, brew, npm, go (default: auto).
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)      CHECK_ONLY=1 ;;
        --dry-run)    DRY_RUN=1 ;;
        -y|--yes)     ASSUME_YES=1 ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_INFO=$'\033[36m'; C_RESET=$'\033[0m'
else
    C_OK=""; C_WARN=""; C_ERR=""; C_INFO=""; C_RESET=""
fi
ok()   { printf '%s[ OK ]%s %s\n'   "$C_OK"   "$C_RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n'   "$C_WARN" "$C_RESET" "$*" >&2; }
err()  { printf '%s[FAIL]%s %s\n'   "$C_ERR"  "$C_RESET" "$*" >&2; }
info() { printf '%s[ .. ]%s %s\n'   "$C_INFO" "$C_RESET" "$*"; }

# Run (or echo, in dry-run mode) an install command.
run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        printf '       would run: %s\n' "$*"
        return 0
    fi
    info "running: $*"
    "$@"
}

confirm() {
    local prompt="$1"
    [[ $ASSUME_YES -eq 1 || $DRY_RUN -eq 1 ]] && return 0
    if [[ ! -t 0 ]]; then
        warn "stdin is not a terminal; re-run with --yes to install non-interactively."
        return 1
    fi
    read -r -p "$prompt [y/N] " answer
    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# version_ge A B  -> true if A >= B (numeric dotted versions)
version_ge() {
    [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]
}

# Return "sudo" when we are not root and sudo exists, "" when root.
SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
    if command -v sudo > /dev/null 2>&1; then
        SUDO="sudo"
    fi
fi

OS="$(uname -s)"
MISSING=()     # required tools still missing at the end
WARNINGS=()    # non-fatal notes for the summary

# ---------------------------------------------------------------------------
# tmux
# ---------------------------------------------------------------------------
tmux_version() {
    tmux -V 2>/dev/null | sed -E 's/^tmux[[:space:]]+//; s/[^0-9.].*$//'
}

install_tmux() {
    if [[ "$OS" == "Darwin" ]]; then
        if command -v brew > /dev/null 2>&1; then
            run brew install tmux; return
        fi
        err "Homebrew not found. Install it from https://brew.sh then re-run, or: brew install tmux"
        return 1
    fi

    if command -v apt-get > /dev/null 2>&1; then
        run $SUDO apt-get update -qq
        run $SUDO apt-get install -y tmux
    elif command -v dnf > /dev/null 2>&1; then
        run $SUDO dnf install -y tmux
    elif command -v yum > /dev/null 2>&1; then
        run $SUDO yum install -y tmux
    elif command -v pacman > /dev/null 2>&1; then
        run $SUDO pacman -Sy --noconfirm tmux
    elif command -v zypper > /dev/null 2>&1; then
        run $SUDO zypper install -y tmux
    elif command -v apk > /dev/null 2>&1; then
        run $SUDO apk add tmux
    elif command -v brew > /dev/null 2>&1; then
        run brew install tmux
    else
        err "No supported package manager found (apt-get, dnf, yum, pacman, zypper, apk, brew)."
        err "Install tmux >= $TMUX_MIN_VERSION manually: https://github.com/tmux/tmux/wiki/Installing"
        return 1
    fi
}

check_tmux() {
    local v
    if command -v tmux > /dev/null 2>&1; then
        v="$(tmux_version)"
        if [[ -n "$v" ]] && version_ge "$v" "$TMUX_MIN_VERSION"; then
            ok "tmux $v found ($(command -v tmux))"
            return 0
        fi
        warn "tmux $v found but >= $TMUX_MIN_VERSION is required (pane titles)."
        WARNINGS+=("tmux is too old ($v); upgrade to >= $TMUX_MIN_VERSION")
        return 0
    fi

    warn "tmux not found."
    if [[ $CHECK_ONLY -eq 1 ]]; then
        MISSING+=("tmux"); return 0
    fi
    if ! confirm "Install tmux with the system package manager?"; then
        MISSING+=("tmux"); return 0
    fi
    if ! install_tmux; then
        MISSING+=("tmux"); return 0
    fi
    if [[ $DRY_RUN -eq 0 ]]; then
        if command -v tmux > /dev/null 2>&1; then
            ok "tmux $(tmux_version) installed."
        else
            err "tmux install finished but the binary is still not on PATH."
            MISSING+=("tmux")
        fi
    fi
}

# ---------------------------------------------------------------------------
# bd (beads)
# ---------------------------------------------------------------------------
bd_version() {
    bd version 2>/dev/null | head -n1 || bd --version 2>/dev/null | head -n1 || true
}

pick_beads_method() {
    local forced="${BEADS_INSTALL_METHOD:-auto}"
    case "$forced" in
        script|brew|npm|go) echo "$forced"; return ;;
        auto) ;;
        *) err "BEADS_INSTALL_METHOD must be one of: script, brew, npm, go"; return 1 ;;
    esac
    if command -v brew > /dev/null 2>&1 && [[ "$OS" == "Darwin" ]]; then
        echo brew
    elif command -v curl > /dev/null 2>&1; then
        echo script
    elif command -v npm > /dev/null 2>&1; then
        echo npm
    elif command -v go > /dev/null 2>&1; then
        echo go
    else
        err "Need one of curl, brew, npm or go to install bd."
        return 1
    fi
}

install_bd() {
    local method
    method="$(pick_beads_method)" || return 1
    info "installing bd via: $method"
    case "$method" in
        brew)
            run brew install beads ;;
        script)
            # Official installer; verifies release checksums and puts bd in ~/.local/bin
            # (or another user-writable bin dir).
            if [[ $DRY_RUN -eq 1 ]]; then
                printf '       would run: curl -fsSL %s | bash\n' "$BEADS_INSTALL_URL"
            else
                info "running: curl -fsSL $BEADS_INSTALL_URL | bash"
                curl -fsSL "$BEADS_INSTALL_URL" | bash
            fi ;;
        npm)
            run npm install -g @beads/bd ;;
        go)
            run env CGO_ENABLED=0 go install -tags gms_pure_go github.com/steveyegge/beads/cmd/bd@latest
            [[ ":$PATH:" == *":$(go env GOPATH)/bin:"* ]] || \
                WARNINGS+=("add $(go env GOPATH)/bin to PATH so 'bd' is found") ;;
    esac
}

check_bd() {
    if command -v bd > /dev/null 2>&1; then
        ok "bd found: $(bd_version) ($(command -v bd))"
        return 0
    fi

    # Common install location that may not be on PATH yet.
    if [[ -x "$HOME/.local/bin/bd" ]]; then
        warn "bd is installed at ~/.local/bin/bd but ~/.local/bin is not on PATH."
        WARNINGS+=("add \$HOME/.local/bin to PATH (export PATH=\"\$HOME/.local/bin:\$PATH\")")
        return 0
    fi

    warn "bd (beads) not found."
    if [[ $CHECK_ONLY -eq 1 ]]; then
        MISSING+=("bd"); return 0
    fi
    if ! confirm "Install bd (beads)?"; then
        MISSING+=("bd"); return 0
    fi
    if ! install_bd; then
        MISSING+=("bd"); return 0
    fi
    if [[ $DRY_RUN -eq 0 ]]; then
        hash -r
        if command -v bd > /dev/null 2>&1; then
            ok "bd installed: $(bd_version)"
        elif [[ -x "$HOME/.local/bin/bd" ]]; then
            ok "bd installed at ~/.local/bin/bd"
            WARNINGS+=("add \$HOME/.local/bin to PATH (export PATH=\"\$HOME/.local/bin:\$PATH\")")
        else
            err "bd install finished but the binary is not on PATH."
            MISSING+=("bd")
        fi
    fi
}

# ---------------------------------------------------------------------------
# Checked-only prerequisites
# ---------------------------------------------------------------------------
check_bash() {
    if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
        ok "bash ${BASH_VERSION%%(*}"
    else
        err "bash >= 4.0 required, found $BASH_VERSION"
        MISSING+=("bash>=4")
    fi
}

check_git() {
    if command -v git > /dev/null 2>&1; then
        ok "$(git --version)"
    else
        err "git not found. Install it with your package manager."
        MISSING+=("git")
    fi
}

check_claude() {
    if command -v claude > /dev/null 2>&1; then
        ok "claude CLI found ($(command -v claude))"
    else
        warn "claude CLI not found. Install Claude Code and authenticate before running workspace.sh:"
        warn "  https://docs.anthropic.com/en/docs/claude-code"
        WARNINGS+=("claude CLI missing; install and run 'claude' once to authenticate")
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo "multiagents-setup environment check ($OS)"
[[ $CHECK_ONLY -eq 1 ]] && echo "(check only, nothing will be installed)"
[[ $DRY_RUN -eq 1 ]]   && echo "(dry run, install commands are printed, not executed)"
echo

check_bash
check_git
check_tmux
check_bd
check_claude

echo
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo "Notes:"
    for w in "${WARNINGS[@]}"; do echo "  - $w"; done
    echo
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
    err "Still missing: ${MISSING[*]}"
    exit 1
fi

if [[ $DRY_RUN -eq 1 ]]; then
    info "Dry run complete."
else
    ok "Environment ready. Run ./workspace.sh from your project directory."
fi
