#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

homedir="$(getent passwd "$USER" | cut -d: -f6)"
config_dir="$homedir/.config"
stamp="$(date +%Y%m%d-%H%M%S)"

banner() {
    echo "-------------------"
    echo "$1"
    echo "-------------------"
}

ask() {
    # ask "question" -> returns 0 on yes
    local reply
    read -r -p "$1 [y/N] " reply
    [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# ----------------------------------------------------------------------
# Dependencies
# ----------------------------------------------------------------------
banner "Checking dependencies"

declare -A fallback_pkg=( [noctalia]=noctalia-git ) # name used if not in the repos

missing=()
for dep in niri noctalia; do
    command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
done

if ! command -v pacman >/dev/null 2>&1; then
    echo "This script only auto-installs dependencies on Arch Linux (pacman)."
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Please install them manually: ${missing[*]}"
        exit 1
    fi
fi

if [ "${#missing[@]}" -gt 0 ]; then
    echo "Missing: ${missing[*]}"
    if ask "Install them now?"; then
        repo_pkgs=()
        aur_pkgs=()
        for dep in "${missing[@]}"; do
            if pacman -Si "$dep" >/dev/null 2>&1; then
                repo_pkgs+=("$dep")
            else
                # not in the repos -> try the AUR (under its own name or the fallback)
                if [ -n "${fallback_pkg[$dep]:-}" ]; then
                    aur_pkgs+=("${fallback_pkg[$dep]}")
                else
                    aur_pkgs+=("$dep")
                fi
            fi
        done

        if [ "${#repo_pkgs[@]}" -gt 0 ]; then
            sudo pacman -S --needed "${repo_pkgs[@]}"
        fi

        if [ "${#aur_pkgs[@]}" -gt 0 ]; then
            aur_helper="$(command -v paru || command -v yay || true)"
            if [ -z "$aur_helper" ]; then
                echo "Error: ${aur_pkgs[*]} is not in the repositories and no AUR helper (paru/yay) is installed."
                exit 1
            fi
            "$aur_helper" -S --needed "${aur_pkgs[@]}"
        fi
    else
        echo "Aborting: required packages are missing."
        exit 1
    fi

    # verify
    still_missing=()
    for dep in "${missing[@]}"; do
        command -v "$dep" >/dev/null 2>&1 || still_missing+=("$dep")
    done
    if [ "${#still_missing[@]}" -gt 0 ]; then
        echo "Error: still missing: ${still_missing[*]}"
        exit 1
    fi
fi

echo "Dependencies ok: niri, noctalia"

# ----------------------------------------------------------------------
# Dotfiles
# ----------------------------------------------------------------------
banner "Installing dotfiles"
echo "Existing configs are backed up first"
echo "ctrl+C to cancel"
echo ""

sleep 3

mkdir -p "$config_dir"

# Merge the repo's directory into $2, backing up what is already there.
copy_dir() {
    local src="$1" dst="$2"
    if [ -e "$dst" ]; then
        cp -a "$dst" "$dst.bak.$stamp"
        echo "Backed up $dst -> $(basename "$dst").bak.$stamp"
    fi
    mkdir -p "$dst"
    cp -a "$src"/. "$dst"/
    echo "Installed $dst"
}

# Same, for a single file.
copy_file() {
    local src="$1" dst="$2"
    if [ -e "$dst" ]; then
        cp -a "$dst" "$dst.bak.$stamp"
        echo "Backed up $dst -> $(basename "$dst").bak.$stamp"
    fi
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
    echo "Installed $dst"
}

copy_dir ./niri "$config_dir/niri"
copy_file ./noctalia/noctalia-config.toml "$config_dir/noctalia/noctalia-config.toml"

# Reload the config if niri is already running
if niri msg version >/dev/null 2>&1; then
    niri msg action load-config-file >/dev/null 2>&1 || true
    echo "Reloaded niri config"
fi

banner "Installed dotfiles. Please relog in your session"
