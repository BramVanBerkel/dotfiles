#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

echo "Installing dotfiles from $DOTFILES_DIR (KDE Plasma)"

# Fail before the long system update rather than halfway through it.
if ! command -v kwriteconfig6 &>/dev/null; then
    echo "kwriteconfig6 not found - this script expects a Fedora KDE install." >&2
    echo "For GNOME, run ./install-gnome.sh instead." >&2
    exit 1
fi

KDE_DIR="$DOTFILES_DIR/kde"
# shellcheck source=kde/config-files.sh
source "$KDE_DIR/config-files.sh"

# plasma-apply-* talk to a running session over D-Bus; kwriteconfig6 does not.
in_plasma_session() {
    [ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ]
}

setup_hostname
setup_dnf_conf
setup_repos

# --- Remove bloat ---
remove_libreoffice

# --- DNF packages ---
install_codecs

# Fedora KDE ships Konsole but not Ptyxis, and plasma-systemmonitor covers what
# Resources does on the GNOME side.
DNF_PACKAGES=(
    ptyxis
    steam
    wl-clipboard
    xremap-kde
    yakuake
    zsh
)

prompt_nvidia
if [[ "$INSTALL_NVIDIA" == true ]]; then
    DNF_PACKAGES+=("${NVIDIA_PACKAGES[@]}")
fi

install_dnf_packages "${DNF_PACKAGES[@]}"
setup_gpu_power_limit

# --- Flatpaks ---
setup_flatpak_remote
install_flatpaks \
    com.bitwarden.desktop \
    com.spotify.Client \
    it.mijorus.gearlever
install_jagex_launcher

# --- Apps ---
install_zen
set_default_browser
install_zed
setup_zsh

# --- xremap ---
setup_xremap

# --- Yakuake ---
echo ""
echo "Setting up Yakuake..."

YAKUAKE_DESKTOP=/usr/share/applications/org.kde.yakuake.desktop
if [ -f "$YAKUAKE_DESKTOP" ]; then
    if [ ! -e "$HOME/.config/autostart/org.kde.yakuake.desktop" ]; then
        echo "  Enabling Yakuake autostart..."
        mkdir -p "$HOME/.config/autostart"
        cp "$YAKUAKE_DESKTOP" "$HOME/.config/autostart/"
    else
        echo "  Yakuake autostart already enabled"
    fi
else
    echo "  Yakuake desktop file not found, skipping autostart"
fi

# --- Plasma config files ---
echo ""
echo "Restoring Plasma config..."

restored_config=false
for config in "${KDE_CONFIGS[@]}"; do
    src="$KDE_DIR/$config"
    dest="$HOME/.config/$config"

    if [ ! -f "$src" ]; then
        echo "  $config not in repo yet, skipping (see kde/export-config.sh)"
        continue
    fi

    if [ -e "$dest" ] && ! cmp -s "$src" "$dest"; then
        echo "  Backing up existing $dest to ${dest}.bak"
        cp "$dest" "${dest}.bak"
    fi

    cp "$src" "$dest"
    echo "  Restored $config"
    restored_config=true
done

# --- Plasma settings ---
echo ""
echo "Configuring Plasma settings..."

# Writes the GNOME mouse settings (speed -0.23, flat acceleration) for every
# connected pointer, since Plasma stores these per device.
configure_mice() {
    local vendor="" product="" name="" line group_name

    while IFS= read -r line; do
        case "$line" in
            "I: "*)
                vendor=$(grep -oP 'Vendor=\K[0-9a-f]+' <<< "$line" || true)
                product=$(grep -oP 'Product=\K[0-9a-f]+' <<< "$line" || true)
                ;;
            'N: Name="'*)
                name=${line#N: Name=\"}
                name=${name%\"}
                ;;
            "H: Handlers="*)
                [[ "$line" == *mouse* ]] || continue
                [ -n "$vendor" ] && [ -n "$product" ] && [ -n "$name" ] || continue
                # xremap's own virtual uinput device, not a real pointer
                [ "$name" != "xremap" ] || continue

                group_name="$name"
                echo "  Configuring pointer: $group_name"
                kwriteconfig6 --file kcminputrc \
                    --group Libinput --group "$((16#$vendor))" --group "$((16#$product))" --group "$group_name" \
                    --key PointerAcceleration -0.230
                kwriteconfig6 --file kcminputrc \
                    --group Libinput --group "$((16#$vendor))" --group "$((16#$product))" --group "$group_name" \
                    --key PointerAccelerationProfile 1
                ;;
        esac
    done < /proc/bus/input/devices
}

echo "  Setting mouse speed and disabling acceleration..."
configure_mice

echo "  Setting window switcher shortcut to Ctrl+Tab..."
kwriteconfig6 --file kglobalshortcutsrc --group kwin \
    --key "Walk Through Windows" "Ctrl+Tab,Alt+Tab,Walk Through Windows"

echo "  Setting KRunner shortcut to Ctrl+Space..."
kwriteconfig6 --file kglobalshortcutsrc --group services --group "org.kde.krunner.desktop" \
    --key "_launch" "Ctrl+Space,Alt+Space,KRunner"

echo "  Setting formats to Dutch..."
kwriteconfig6 --file plasma-localerc --group Formats --key LANG nl_NL.UTF-8

set_wallpaper_file

if in_plasma_session; then
    echo "  Enabling dark mode..."
    plasma-apply-lookandfeel -a org.kde.breezedark.desktop

    echo "  Setting wallpaper..."
    plasma-apply-wallpaperimage "$HOME/.config/background"

    if [ "$restored_config" = true ]; then
        echo "  Restarting plasmashell..."
        kquitapp6 plasmashell && kstart plasmashell
    fi

    echo "  Reloading global shortcuts..."
    kquitapp6 kglobalacceld 2>/dev/null || true
else
    echo "  Not in a Plasma session, skipping theme/wallpaper (re-run from Plasma)"
fi

# --- Cleanup ---
cleanup
prompt_reboot
