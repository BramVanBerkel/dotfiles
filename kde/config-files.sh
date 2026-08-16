#!/bin/bash
# Plasma config files tracked in this repo, relative to ~/.config.
# Sourced by install-kde.sh (restore) and kde/export-config.sh (capture).
#
# These are copied rather than symlinked: Plasma rewrites them at runtime, so a
# symlink would let every session dirty the repo. Run export-config.sh when you
# have deliberately changed the panel or a shortcut and want it committed.

# shellcheck disable=SC2034  # consumed by install-kde.sh and export-config.sh
KDE_CONFIGS=(
    plasma-org.kde.plasma.desktop-appletsrc
    kglobalshortcutsrc
)
