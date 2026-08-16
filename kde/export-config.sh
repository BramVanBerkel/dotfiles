#!/bin/bash
# Copies the tracked Plasma config out of ~/.config and into this repo, so a
# panel layout / shortcut set arranged by hand can be committed and restored by
# install-kde.sh on the next machine.
set -euo pipefail

KDE_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=kde/config-files.sh
source "$KDE_DIR/config-files.sh"

echo "Exporting Plasma config to $KDE_DIR"

for config in "${KDE_CONFIGS[@]}"; do
    src="$HOME/.config/$config"

    if [ ! -f "$src" ]; then
        echo "  $config not found in ~/.config, skipping"
        continue
    fi

    cp "$src" "$KDE_DIR/$config"
    echo "  Exported $config"
done

echo ""
echo "Done. Review with 'git diff' before committing."
