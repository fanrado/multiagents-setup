#!/usr/bin/env bash
# Sourced by workspace.sh before any tmux command.
#
# setup.sh installs tmux from conda-forge into a dedicated conda env
# (MULTIAGENTS_CONDA_ENV, default "multiagents-tools") when conda is available.
# If that env exists, activate it here so tmux — and anything else installed in
# it — is on PATH for workspace.sh, the tmux server it starts, and therefore
# every agent pane (they inherit the server's environment).
#
# Does nothing when conda/mamba/micromamba or the env is absent, or when the
# env is already active. Never fails the caller.

activate_tools_env() {
    local env_name="${MULTIAGENTS_CONDA_ENV:-multiagents-tools}"
    local tool hook prefix

    [[ "${CONDA_DEFAULT_ENV:-}" == "$env_name" ]] && return 0

    for tool in conda mamba micromamba; do
        command -v "$tool" > /dev/null 2>&1 || continue

        # "<name>  <path>" rows; the active env carries a '*' in between.
        prefix="$("$tool" env list 2>/dev/null | awk -v n="$env_name" '$1 == n { print $NF; exit }')"
        [[ -n "$prefix" && -d "$prefix" ]] || continue

        case "$tool" in
            conda) hook="$(conda shell.bash hook 2>/dev/null)" ;;
            *)     hook="$("$tool" shell hook -s bash 2>/dev/null)" ;;
        esac

        if [[ -n "$hook" ]] && eval "$hook" && "$tool" activate "$env_name" 2>/dev/null; then
            echo "conda: activated env '$env_name' ($prefix)" >&2
        else
            # Activation hook unavailable (unusual); fall back to exposing the env's bin dir.
            export PATH="$prefix/bin:$PATH"
            echo "conda: could not activate '$env_name'; added $prefix/bin to PATH instead" >&2
        fi
        return 0
    done
    return 0
}
