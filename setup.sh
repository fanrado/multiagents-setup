#!/usr/bin/env bash
# setup.sh — prepare a machine to run the multiagents workspace, without root.
#
# Checks for the tools workspace.sh depends on and installs the missing ones
# into user space (nothing here needs sudo by default):
#   - tmux  (>= 2.6)   -> conda-forge / Homebrew / static binary in ~/.local/bin
#   - bd    (beads)    -> official installer into ~/.local/bin / brew / npm / go
#   - claude (Claude Code CLI), git, bash >= 4  -> checked only, never installed
#
# Usage: ./setup.sh [--check] [--dry-run] [--yes] [-h]
set -euo pipefail

TMUX_MIN_VERSION="2.6"
LOCAL_BIN="${LOCAL_BIN:-$HOME/.local/bin}"
# Env name shared with workspace.sh, which activates it via scripts/conda_env.sh.
SETUP_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config/workspace.conf
[[ -r "$SETUP_DIR/config/workspace.conf" ]] && source "$SETUP_DIR/config/workspace.conf"
CONDA_ENV_NAME="${CONDA_ENV_NAME:-${MULTIAGENTS_CONDA_ENV:-multiagents-tools}}"
# If the env already exists, put its tmux on PATH the same way workspace.sh does.
# shellcheck source=scripts/conda_env.sh
if [[ -r "$SETUP_DIR/scripts/conda_env.sh" ]]; then
    source "$SETUP_DIR/scripts/conda_env.sh"
    MULTIAGENTS_CONDA_ENV="$CONDA_ENV_NAME" activate_tools_env 2>/dev/null || true
fi
BEADS_INSTALL_URL="https://raw.githubusercontent.com/gastownhall/beads/main/scripts/install.sh"
# Statically linked tmux (musl + ncurses + libevent), Linux x86_64 only.
TMUX_STATIC_REPO="mjakob-gh/build-static-tmux"
TMUX_STATIC_URL="https://github.com/$TMUX_STATIC_REPO/releases/latest/download/tmux.linux-amd64.gz"

CHECK_ONLY=0
DRY_RUN=0
ASSUME_YES=0

usage() {
    cat <<USAGE
Usage: $(basename "$0") [OPTIONS]

Checks that tmux and bd (beads) are installed and installs them if missing.
Everything is installed into user space (~/.local/bin, conda, or Homebrew);
no sudo is required. Also reports on git, bash and the claude CLI, which are
required but not installed by this script.

Options:
  --check      Only report what is installed/missing; never install (exit 1 if
               anything required is missing).
  --dry-run    Print the install commands that would run, without running them.
  -y, --yes    Do not prompt before installing.
  -h, --help   Show this help.

Environment:
  TMUX_INSTALL_METHOD    Force one of: conda, brew, static, pkg (default: auto).
                         'pkg' uses the system package manager and needs sudo;
                         it is never chosen automatically.
  BEADS_INSTALL_METHOD   Force one of: script, brew, npm, go (default: auto).
  LOCAL_BIN              Where user-space binaries go (default: ~/.local/bin).
  CONDA_ENV_NAME         Conda env used for tmux (default: MULTIAGENTS_CONDA_ENV from
                         config/workspace.conf, i.e. multiagents-tools).
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

has() { command -v "$1" > /dev/null 2>&1; }

OS="$(uname -s)"
ARCH="$(uname -m)"
MISSING=()     # required tools still missing at the end
WARNINGS=()    # non-fatal notes for the summary
LOCAL_BIN_NOTE_ADDED=0

# Make sure ~/.local/bin exists and remember to tell the user if it is not on PATH.
ensure_local_bin() {
    [[ $DRY_RUN -eq 1 ]] || mkdir -p "$LOCAL_BIN"
    if [[ ":$PATH:" != *":$LOCAL_BIN:"* && $LOCAL_BIN_NOTE_ADDED -eq 0 ]]; then
        WARNINGS+=("$LOCAL_BIN is not on PATH. Add to ~/.bashrc or ~/.zshrc:  export PATH=\"$LOCAL_BIN:\$PATH\"")
        LOCAL_BIN_NOTE_ADDED=1
    fi
}

# First available conda-style tool, or nothing.
conda_cmd() {
    local c
    for c in micromamba mamba conda; do
        if has "$c"; then echo "$c"; return 0; fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# tmux
# ---------------------------------------------------------------------------
tmux_version() {
    tmux -V 2>/dev/null | sed -E 's/^tmux[[:space:]]+//; s/[^0-9.].*$//'
}

pick_tmux_method() {
    local forced="${TMUX_INSTALL_METHOD:-auto}"
    case "$forced" in
        conda|brew|static|pkg) echo "$forced"; return ;;
        auto) ;;
        *) err "TMUX_INSTALL_METHOD must be one of: conda, brew, static, pkg"; return 1 ;;
    esac
    if conda_cmd > /dev/null; then
        echo conda
    elif has brew; then
        echo brew
    elif [[ "$OS" == "Linux" && "$ARCH" == "x86_64" ]] && has curl; then
        echo static
    else
        err "No user-space install route for tmux on $OS/$ARCH."
        err "Options: install conda/micromamba (https://mamba.readthedocs.io) or Homebrew (https://brew.sh)"
        err "and re-run; or build tmux from source into $LOCAL_BIN; or run with"
        err "TMUX_INSTALL_METHOD=pkg to use the system package manager (needs sudo)."
        return 1
    fi
}

# Install tmux from conda-forge into a dedicated env, leaving base untouched.
# workspace.sh activates this env automatically (scripts/conda_env.sh); the
# symlink in LOCAL_BIN additionally makes `tmux attach` work from a plain shell.
install_tmux_conda() {
    local c prefix
    c="$(conda_cmd)" || { err "no conda/mamba/micromamba on PATH"; return 1; }
    ensure_local_bin
    run "$c" create -y -n "$CONDA_ENV_NAME" -c conda-forge tmux
    if [[ $DRY_RUN -eq 1 ]]; then
        printf '       would run: ln -sf <%s env>/bin/tmux %s/tmux\n' "$CONDA_ENV_NAME" "$LOCAL_BIN"
        return 0
    fi
    prefix="$("$c" run -n "$CONDA_ENV_NAME" sh -c 'echo "$CONDA_PREFIX"' 2>/dev/null | tail -n1)"
    if [[ -z "$prefix" || ! -x "$prefix/bin/tmux" ]]; then
        err "conda env '$CONDA_ENV_NAME' was created but tmux binary not found in it."
        return 1
    fi
    run ln -sf "$prefix/bin/tmux" "$LOCAL_BIN/tmux"
}

# Download a statically linked tmux release into LOCAL_BIN.
install_tmux_static() {
    if [[ "$OS" != "Linux" || "$ARCH" != "x86_64" ]]; then
        err "static tmux binaries are only published for Linux x86_64 (this is $OS/$ARCH)."
        return 1
    fi
    has curl || { err "curl is required to download the static tmux binary."; return 1; }
    ensure_local_bin
    info "static binary source: https://github.com/$TMUX_STATIC_REPO (musl + ncurses + libevent)"
    if [[ $DRY_RUN -eq 1 ]]; then
        printf '       would run: curl -fsSL %s | gunzip > %s/tmux && chmod +x %s/tmux\n' \
            "$TMUX_STATIC_URL" "$LOCAL_BIN" "$LOCAL_BIN"
        return 0
    fi
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/tmux.XXXXXX")"
    info "downloading $TMUX_STATIC_URL"
    if ! curl -fsSL "$TMUX_STATIC_URL" | gunzip > "$tmp"; then
        rm -f "$tmp"; err "download failed."; return 1
    fi
    chmod 755 "$tmp"
    if ! "$tmp" -V > /dev/null 2>&1; then
        rm -f "$tmp"; err "downloaded tmux binary does not run on this system."; return 1
    fi
    mv "$tmp" "$LOCAL_BIN/tmux"
}

# System package manager. Opt-in only (TMUX_INSTALL_METHOD=pkg); needs sudo.
install_tmux_pkg() {
    local sudo=""
    [[ "$(id -u)" -eq 0 ]] || sudo="sudo"
    if has apt-get;    then run $sudo apt-get update -qq; run $sudo apt-get install -y tmux
    elif has dnf;      then run $sudo dnf install -y tmux
    elif has yum;      then run $sudo yum install -y tmux
    elif has pacman;   then run $sudo pacman -Sy --noconfirm tmux
    elif has zypper;   then run $sudo zypper install -y tmux
    elif has apk;      then run $sudo apk add tmux
    else err "No supported system package manager found."; return 1
    fi
}

install_tmux() {
    local method
    method="$(pick_tmux_method)" || return 1
    info "installing tmux via: $method"
    case "$method" in
        conda)  install_tmux_conda ;;
        brew)   run brew install tmux ;;
        static) install_tmux_static ;;
        pkg)    install_tmux_pkg ;;
    esac
}

# When tmux comes from the conda env, make sure LOCAL_BIN/tmux points at it so
# `tmux attach` also works from a plain shell where the env is not activated.
link_conda_tmux() {
    local tmux_path
    tmux_path="$(command -v tmux)"
    [[ -n "${CONDA_PREFIX:-}" && "$tmux_path" == "$CONDA_PREFIX/bin/tmux" ]] || return 0
    [[ -e "$LOCAL_BIN/tmux" ]] && return 0
    if [[ $CHECK_ONLY -eq 1 ]]; then
        WARNINGS+=("tmux is only reachable inside conda env '$CONDA_ENV_NAME' (workspace.sh activates it); run setup.sh without --check to add a $LOCAL_BIN/tmux symlink for plain shells")
        return 0
    fi
    ensure_local_bin
    run ln -sf "$tmux_path" "$LOCAL_BIN/tmux"
}

check_tmux() {
    local v
    if has tmux; then
        v="$(tmux_version)"
        if [[ -n "$v" ]] && version_ge "$v" "$TMUX_MIN_VERSION"; then
            ok "tmux $v found ($(command -v tmux))"
            [[ "${CONDA_DEFAULT_ENV:-}" == "$CONDA_ENV_NAME" ]] && \
                info "tmux comes from conda env '$CONDA_ENV_NAME'; workspace.sh activates it automatically."
            link_conda_tmux
            return 0
        fi
        warn "tmux $v found but >= $TMUX_MIN_VERSION is required (pane titles)."
        WARNINGS+=("tmux is too old ($v); upgrade to >= $TMUX_MIN_VERSION")
        return 0
    fi
    if [[ -x "$LOCAL_BIN/tmux" ]]; then
        warn "tmux is installed at $LOCAL_BIN/tmux but that directory is not on PATH."
        ensure_local_bin
        return 0
    fi

    warn "tmux not found."
    if [[ $CHECK_ONLY -eq 1 ]]; then MISSING+=("tmux"); return 0; fi
    if ! confirm "Install tmux (user space, no sudo)?"; then MISSING+=("tmux"); return 0; fi
    if ! install_tmux; then MISSING+=("tmux"); return 0; fi
    if [[ $DRY_RUN -eq 0 ]]; then
        hash -r
        if has tmux; then
            ok "tmux $(tmux_version) installed ($(command -v tmux))."
        elif [[ -x "$LOCAL_BIN/tmux" ]]; then
            ok "$("$LOCAL_BIN/tmux" -V) installed at $LOCAL_BIN/tmux."
            ensure_local_bin
        else
            err "tmux install finished but the binary is not on PATH."
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

# npm -g only works without sudo when the global prefix is user-writable.
npm_global_writable() {
    has npm || return 1
    local prefix
    prefix="$(npm prefix -g 2>/dev/null)" || return 1
    [[ -w "$prefix" || -w "$prefix/lib" ]]
}

pick_beads_method() {
    local forced="${BEADS_INSTALL_METHOD:-auto}"
    case "$forced" in
        script|brew|npm|go) echo "$forced"; return ;;
        auto) ;;
        *) err "BEADS_INSTALL_METHOD must be one of: script, brew, npm, go"; return 1 ;;
    esac
    if has curl; then
        echo script
    elif has brew; then
        echo brew
    elif npm_global_writable; then
        echo npm
    elif has go; then
        echo go
    else
        err "Need one of curl, brew, npm (user-writable prefix) or go to install bd."
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
            # Official installer: verifies release checksums, installs into ~/.local/bin.
            ensure_local_bin
            if [[ $DRY_RUN -eq 1 ]]; then
                printf '       would run: curl -fsSL %s | bash\n' "$BEADS_INSTALL_URL"
            else
                info "running: curl -fsSL $BEADS_INSTALL_URL | bash"
                # The installer exits non-zero when LOCAL_BIN is not on PATH even
                # though bd was installed; check_bd verifies the binary afterwards.
                curl -fsSL "$BEADS_INSTALL_URL" | bash || true
            fi ;;
        npm)
            if ! npm_global_writable; then
                err "npm global prefix ($(npm prefix -g 2>/dev/null)) is not writable without sudo."
                err "Use BEADS_INSTALL_METHOD=script, or: npm config set prefix ~/.local"
                return 1
            fi
            run npm install -g @beads/bd ;;
        go)
            run env CGO_ENABLED=0 go install -tags gms_pure_go github.com/steveyegge/beads/cmd/bd@latest
            [[ ":$PATH:" == *":$(go env GOPATH)/bin:"* ]] || \
                WARNINGS+=("add $(go env GOPATH)/bin to PATH so 'bd' is found") ;;
    esac
}

check_bd() {
    if has bd; then
        ok "bd found: $(bd_version) ($(command -v bd))"
        return 0
    fi
    if [[ -x "$LOCAL_BIN/bd" ]]; then
        warn "bd is installed at $LOCAL_BIN/bd but that directory is not on PATH."
        ensure_local_bin
        return 0
    fi

    warn "bd (beads) not found."
    if [[ $CHECK_ONLY -eq 1 ]]; then MISSING+=("bd"); return 0; fi
    if ! confirm "Install bd (beads) (user space, no sudo)?"; then MISSING+=("bd"); return 0; fi
    if ! install_bd; then MISSING+=("bd"); return 0; fi
    if [[ $DRY_RUN -eq 0 ]]; then
        hash -r
        if has bd; then
            ok "bd installed: $(bd_version)"
        elif [[ -x "$LOCAL_BIN/bd" ]]; then
            ok "bd installed at $LOCAL_BIN/bd"
            ensure_local_bin
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
    if has git; then
        ok "$(git --version)"
    else
        err "git not found. Install it with your package manager (or conda: conda install -c conda-forge git)."
        MISSING+=("git")
    fi
}

check_claude() {
    if has claude; then
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
echo "multiagents-setup environment check ($OS/$ARCH, user-space install, no sudo)"
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
