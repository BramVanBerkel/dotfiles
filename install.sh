#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

echo "Installing dotfiles from $DOTFILES_DIR (GNOME)"

setup_hostname
setup_dnf_conf
setup_repos

# --- Remove bloat ---
remove_libreoffice

echo "Removing GNOME System Monitor..."
if rpm -q gnome-system-monitor &>/dev/null; then
    sudo dnf remove -y gnome-system-monitor
else
    echo "  GNOME System Monitor already removed"
fi

# --- DNF packages ---
install_codecs

DNF_PACKAGES=(
    pipx
    steam
    wl-clipboard
    xremap-gnome
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
    com.adamcake.Bolt \
    com.bitwarden.desktop \
    com.spotify.Client \
    it.mijorus.gearlever \
    net.nokyan.Resources \
    com.mattjakeman.ExtensionManager

# --- Apps ---
install_zen
set_default_browser
install_zed
setup_zsh

# --- xremap ---
setup_xremap

# --- GNOME extensions ---
echo ""
echo "Installing GNOME extensions..."

if ! command -v gext &>/dev/null; then
    echo "  Installing gnome-extensions-cli..."
    pipx install gnome-extensions-cli
fi

GNOME_EXTENSIONS=(
    "dash-to-panel@jderose9.github.com"
    "appindicatorsupport@rgcjonas.gmail.com"
    "ddterm@amezin.github.com"
    "xremap@k0kubun.com"
)

for ext in "${GNOME_EXTENSIONS[@]}"; do
    if ! gnome-extensions list | grep -q "$ext"; then
        echo "  Installing $ext..."
        gext install "$ext"
    else
        echo "  $ext already installed"
    fi
    gext enable "$ext"
done

echo "  Disabling background logo..."
gnome-extensions disable "background-logo@fedorahosted.org" 2>/dev/null || true

echo "  Restoring extension configs..."
dconf load /org/gnome/shell/extensions/dash-to-panel/ < "$DOTFILES_DIR/gnome-extensions/dash-to-panel.conf"

# --- GNOME settings ---
echo ""
echo "Configuring GNOME settings..."

echo "  Enabling minimize and maximize buttons..."
gsettings set org.gnome.desktop.wm.preferences button-layout ':minimize,maximize,close'

echo "  Setting mouse speed..."
gsettings set org.gnome.desktop.peripherals.mouse speed -0.23

echo "  Disabling mouse acceleration..."
gsettings set org.gnome.desktop.peripherals.mouse accel-profile 'flat'

echo "  Showing seconds on clock..."
gsettings set org.gnome.desktop.interface clock-show-seconds true

echo "  Enabling dark mode..."
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

echo "  Setting window switcher shortcut to Ctrl+Tab..."
gsettings set org.gnome.desktop.wm.keybindings switch-windows "['<Primary>Tab']"

echo "  Setting pinned apps..."
gsettings set org.gnome.shell favorite-apps "['zen.desktop', 'org.gnome.Ptyxis.desktop', 'org.gnome.Nautilus.desktop', 'dev.zed.Zed.desktop', 'com.adamcake.Bolt.desktop', 'steam.desktop']"

echo "  Setting formats to Dutch..."
gsettings set org.gnome.system.locale region 'nl_NL.UTF-8'

echo "  Setting wallpaper..."
set_wallpaper_file
gsettings set org.gnome.desktop.background picture-uri "file://$HOME/.config/background"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$HOME/.config/background"

# --- Cleanup ---
cleanup
prompt_reboot
