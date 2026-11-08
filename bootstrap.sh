#!/bin/bash
# Installs the dotfiles without cloning by hand:
#   bash <(curl -fsSL https://raw.githubusercontent.com/BramVanBerkel/dotfiles/main/bootstrap.sh)
#
# Clones the repo (or updates an existing clone) and runs install.sh from it.
# The repo has to stay on disk afterwards: install.sh symlinks configs into it.
set -euo pipefail

REPO_URL="https://github.com/BramVanBerkel/dotfiles.git"
TARGET_DIR="${DOTFILES_DIR:-$HOME/Documents/dotfiles}"

# Everything runs from main, so a partially downloaded script does nothing.
main() {
    if ! command -v git &>/dev/null; then
        echo "Installing git..."
        sudo dnf install -y git
    fi

    if [ -d "$TARGET_DIR/.git" ]; then
        echo "Updating existing clone in $TARGET_DIR..."
        git -C "$TARGET_DIR" pull --ff-only \
            || echo "  Couldn't update, continuing with the local copy"
    elif [ -e "$TARGET_DIR" ]; then
        echo "$TARGET_DIR already exists and isn't a git clone, stopping." >&2
        echo "Move it away, or set DOTFILES_DIR to clone somewhere else." >&2
        exit 1
    else
        echo "Cloning dotfiles into $TARGET_DIR..."
        mkdir -p "$(dirname "$TARGET_DIR")"
        git clone "$REPO_URL" "$TARGET_DIR"
    fi

    exec "$TARGET_DIR/install.sh"
}

main "$@"
