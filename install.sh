#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing dotfiles from $DOTFILES_DIR"

# --- DNF configuration ---
echo ""
echo "Optimizing DNF configuration..."

if ! grep -q "max_parallel_downloads" /etc/dnf/dnf.conf 2>/dev/null; then
    echo "  Setting max_parallel_downloads=10..."
    echo "max_parallel_downloads=10" | sudo tee -a /etc/dnf/dnf.conf > /dev/null
else
    echo "  max_parallel_downloads already configured"
fi

echo "  Updating system..."
sudo dnf upgrade --refresh -y

echo "  Updating firmware..."
sudo fwupdmgr refresh --force || true
sudo fwupdmgr update -y || true

# --- Repositories ---
echo ""
echo "Setting up repositories..."

# RPM Fusion (free + nonfree)
if ! rpm -q rpmfusion-free-release &>/dev/null || ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
    echo "  Enabling RPM Fusion (free + nonfree)..."
    sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
else
    echo "  RPM Fusion already enabled"
fi

# Cisco OpenH264
echo "  Enabling Cisco OpenH264 repo..."
sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1

# COPR repos
COPR_REPOS=(
    "blakegardner/xremap"
)

for repo in "${COPR_REPOS[@]}"; do
    if ! dnf copr list --enabled 2>/dev/null | grep -q "$repo"; then
        echo "  Enabling COPR repo $repo..."
        sudo dnf copr enable -y "$repo"
    else
        echo "  COPR $repo already enabled"
    fi
done

# --- DNF Packages ---
echo ""
echo "Installing DNF packages..."

# Media codecs
echo "  Installing multimedia codecs..."
if rpm -q ffmpeg-free &>/dev/null; then
    sudo dnf swap ffmpeg-free ffmpeg --allowerasing -y
else
    echo "  ffmpeg already swapped"
fi
sudo dnf group upgrade multimedia --exclude=PackageKit-gstreamer-plugin -y
sudo dnf group upgrade sound-and-video -y

DNF_PACKAGES=(
    xremap-gnome
    zsh
)

NVIDIA_PACKAGES=(
    akmod-nvidia
    xorg-x11-drv-nvidia
    xorg-x11-drv-nvidia-cuda
)

read -rp "Install NVIDIA drivers? [y/N] " nvidia_choice
if [[ "$nvidia_choice" =~ ^[Yy]$ ]]; then
    DNF_PACKAGES+=("${NVIDIA_PACKAGES[@]}")
fi

for pkg in "${DNF_PACKAGES[@]}"; do
    if ! rpm -q "$pkg" &>/dev/null; then
        echo "  Installing $pkg..."
        sudo dnf install -y "$pkg"
    else
        echo "  $pkg already installed"
    fi
done

# --- Flatpaks ---
echo ""
echo "Setting up Flatpak..."

echo "  Enabling Flathub..."
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "Installing Flatpaks..."

FLATPAKS=(
    com.bitwarden.desktop
    com.jagexlauncher.JagexLauncher
    com.spotify.Client
    com.valvesoftware.Steam
    it.mijorus.gearlever
    net.nokyan.Resources
    com.mattjakeman.ExtensionManager
)

for app in "${FLATPAKS[@]}"; do
    if ! flatpak info "$app" &>/dev/null; then
        echo "  Installing $app..."
        flatpak install -y flathub "$app"
    else
        echo "  $app already installed"
    fi
done

# --- Zsh ---
echo ""
echo "Setting up Zsh..."

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "  Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

if ! grep -q 'alias open="xdg-open"' "$HOME/.zshrc" 2>/dev/null; then
    echo "  Adding open alias..."
    echo 'alias open="xdg-open"' >> "$HOME/.zshrc"
fi

if [ "$SHELL" != "$(which zsh)" ]; then
    echo "  Setting Zsh as default shell..."
    chsh -s "$(which zsh)"
fi

# --- xremap config ---
echo ""
echo "Setting up xremap config..."

XREMAP_SRC="$DOTFILES_DIR/xremap/config.yml"
XREMAP_DEST="$HOME/.config/xremap/config.yml"

mkdir -p "$(dirname "$XREMAP_DEST")"

if [ -e "$XREMAP_DEST" ] && [ ! -L "$XREMAP_DEST" ]; then
    echo "  Backing up existing $XREMAP_DEST to ${XREMAP_DEST}.bak"
    mv "$XREMAP_DEST" "${XREMAP_DEST}.bak"
fi

ln -sf "$XREMAP_SRC" "$XREMAP_DEST"
echo "  Linked $XREMAP_DEST -> $XREMAP_SRC"

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
    "search-light@icedman.github.com"
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

echo "  Restoring extension configs..."
dconf load /org/gnome/shell/extensions/dash-to-panel/ < "$DOTFILES_DIR/gnome-extensions/dash-to-panel.conf"
dconf load /org/gnome/shell/extensions/search-light/ < "$DOTFILES_DIR/gnome-extensions/search-light.conf"

# --- GNOME settings ---
echo ""
echo "Configuring GNOME settings..."

echo "  Enabling minimize and maximize buttons..."
gsettings set org.gnome.desktop.wm.preferences button-layout ':minimize,maximize,close'

echo "  Setting mouse speed..."
gsettings set org.gnome.desktop.peripherals.mouse speed -0.23

echo "  Disabling mouse acceleration..."
gsettings set org.gnome.desktop.peripherals.mouse accel-profile 'flat'

echo "  Enabling dark mode..."
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

echo "  Setting wallpaper..."
cp "$DOTFILES_DIR/wallpaper.jpg" "$HOME/.config/background"
gsettings set org.gnome.desktop.background picture-uri "file://$HOME/.config/background"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$HOME/.config/background"

echo ""
echo "Done!"
