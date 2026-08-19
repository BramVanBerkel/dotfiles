#!/bin/bash
# Implementation of each step of the Fedora setup.
# Sourced by install.sh; defines functions only.

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Helpers ---

# Symlink a file from the repo, backing up anything real that is in the way.
link_config() {
    local src="$1" dest="$2"

    mkdir -p "$(dirname "$dest")"

    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        echo "  Backing up existing $dest to ${dest}.bak"
        mv "$dest" "${dest}.bak"
    fi

    ln -sf "$src" "$dest"
    echo "  Linked $dest -> $src"
}

# --- Hostname ---

setup_hostname() {
    echo ""
    echo "Setting hostname..."
    if [ "$(hostnamectl hostname)" != "fedora" ]; then
        sudo hostnamectl set-hostname fedora
        echo "  Hostname set to fedora"
    else
        echo "  Hostname already set"
    fi
}

# --- DNF configuration ---

setup_dnf_conf() {
    echo ""
    echo "Optimizing DNF configuration..."

    if ! grep -q "max_parallel_downloads" /etc/dnf/dnf.conf 2>/dev/null; then
        echo "  Setting max_parallel_downloads=10..."
        echo "max_parallel_downloads=10" | sudo tee -a /etc/dnf/dnf.conf > /dev/null
    else
        echo "  max_parallel_downloads already configured"
    fi

    echo "  Updating system..."
    sudo dnf update --refresh -y

    echo "  Updating firmware..."
    sudo fwupdmgr refresh --force || true
    sudo fwupdmgr update -y || true
}

# --- Repositories ---

COPR_REPOS=(
    "blakegardner/xremap"
)

setup_repos() {
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

    local repo
    for repo in "${COPR_REPOS[@]}"; do
        if ! dnf copr list --enabled 2>/dev/null | grep -q "$repo"; then
            echo "  Enabling COPR repo $repo..."
            sudo dnf copr enable -y "$repo"
        else
            echo "  COPR $repo already enabled"
        fi
    done
}

# --- Remove bloat ---

remove_libreoffice() {
    echo ""
    echo "Removing LibreOffice..."
    if rpm -qa | grep -q libreoffice; then
        sudo dnf remove -y "libreoffice*"
    else
        echo "  LibreOffice already removed"
    fi
}

# --- Packages ---

install_codecs() {
    echo ""
    echo "Installing multimedia codecs..."
    if rpm -q ffmpeg-free &>/dev/null; then
        sudo dnf swap ffmpeg-free ffmpeg --allowerasing -y
    else
        echo "  ffmpeg already swapped"
    fi
    # install, not upgrade: dnf only upgrades a group that is already marked
    # installed and errors out otherwise, which would abort the whole script.
    # install works either way, and adds the RPM Fusion codecs that only became
    # available once the repos above were enabled.
    sudo dnf group install multimedia --exclude=PackageKit-gstreamer-plugin -y
}

install_dnf_packages() {
    echo ""
    echo "Installing DNF packages..."

    local pkg
    local missing=()
    for pkg in "$@"; do
        if ! rpm -q "$pkg" &>/dev/null; then
            missing+=("$pkg")
        else
            echo "  $pkg already installed"
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "  Installing ${missing[*]}..."
        sudo dnf install -y "${missing[@]}"
    fi
}

# --- NVIDIA ---

# shellcheck disable=SC2034  # consumed by install.sh
NVIDIA_PACKAGES=(
    akmod-nvidia
    xorg-x11-drv-nvidia
    xorg-x11-drv-nvidia-cuda
)

INSTALL_NVIDIA=false
GPU_POWER_LIMIT=200

# Asks whether to install NVIDIA drivers. Sets INSTALL_NVIDIA and
# GPU_POWER_LIMIT; the caller appends NVIDIA_PACKAGES to its own package list.
prompt_nvidia() {
    local nvidia_choice gpu_choice

    read -rp "Install NVIDIA drivers? [y/N] " nvidia_choice
    if [[ "$nvidia_choice" =~ ^[Yy]$ ]]; then
        INSTALL_NVIDIA=true
        read -rp "GPU power limit in watts? [200] " gpu_choice
        GPU_POWER_LIMIT=${gpu_choice:-200}
    fi
}

setup_gpu_power_limit() {
    [[ "$INSTALL_NVIDIA" == true ]] || return 0

    echo ""
    echo "Setting up GPU power limit service (${GPU_POWER_LIMIT}W)..."
    cat <<EOF | sudo tee /etc/systemd/system/gpu-power-limit.service > /dev/null
[Unit]
Description=GPU power limiter
After=nvidia-persistenced.service

[Service]
User=root
Type=oneshot
Restart=never
RemainAfterExit=yes
ExecStart=/usr/bin/bash -c "nvidia-smi -pl ${GPU_POWER_LIMIT}"

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable gpu-power-limit.service
    echo "  gpu-power-limit.service installed and enabled"
}

# --- Flatpaks ---

setup_flatpak_remote() {
    echo ""
    echo "Setting up Flatpak..."

    echo "  Enabling Flathub..."
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

install_flatpaks() {
    echo "Installing Flatpaks..."

    local app
    local missing=()
    for app in "$@"; do
        if ! flatpak info "$app" &>/dev/null; then
            missing+=("$app")
        else
            echo "  $app already installed"
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "  Installing ${missing[*]}..."
        flatpak install -y flathub "${missing[@]}"
    fi
}

# --- AppImages ---

install_zen() {
    echo ""
    echo "Installing AppImages..."

    mkdir -p "$HOME/Applications"

    if ! flatpak run it.mijorus.gearlever --list-installed 2>/dev/null | grep -qi zen; then
        echo "  Installing Zen Browser..."
        local zen_version zen_url zen_file
        zen_version=$(curl -fSs https://api.github.com/repos/zen-browser/desktop/releases/latest | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
        zen_url="https://github.com/zen-browser/desktop/releases/download/${zen_version}/zen-x86_64.AppImage"
        zen_file="$HOME/Applications/zen-x86_64.AppImage"
        curl -fSL -o "$zen_file" "$zen_url"
        chmod +x "$zen_file"
        flatpak run it.mijorus.gearlever --integrate "$zen_file"
    else
        echo "  Zen Browser already installed"
    fi
}

set_default_browser() {
    echo "  Setting Zen as default browser..."
    local zen_desktop
    zen_desktop=$(grep -rli "name=zen" "$HOME/.local/share/applications/" --include="*.desktop" 2>/dev/null | head -1 | xargs -r basename)
    if [ -n "$zen_desktop" ]; then
        xdg-settings set default-web-browser "$zen_desktop" || echo "  Could not set default browser"
    else
        echo "  Could not find Zen desktop file, skipping"
    fi
}

# --- Zed ---

install_zed() {
    echo ""
    echo "Installing Zed editor..."

    if [ ! -d "$HOME/.local/zed.app" ]; then
        curl -f https://zed.dev/install.sh | sh
    else
        echo "  Zed already installed"
    fi
}

# --- Zsh ---

setup_zsh() {
    echo ""
    echo "Setting up Zsh..."

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        echo "  Installing Oh My Zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi

    # shellcheck disable=SC2016  # $HOME is literal text in .zshrc, not expanded here
    if grep -q '^# export PATH=$HOME/bin:$HOME/.local/bin' "$HOME/.zshrc" 2>/dev/null; then
        echo "  Uncommenting PATH export..."
        sed -i 's/^# export PATH=$HOME\/bin:$HOME\/.local\/bin/export PATH=$HOME\/bin:$HOME\/.local\/bin/' "$HOME/.zshrc"
    fi

    if ! grep -q 'alias open="xdg-open"' "$HOME/.zshrc" 2>/dev/null; then
        echo "  Adding open alias..."
        echo 'alias open="xdg-open"' >> "$HOME/.zshrc"
    fi

    if ! grep -q 'alias pbcopy="wl-copy"' "$HOME/.zshrc" 2>/dev/null; then
        echo "  Adding pbcopy/pbpaste aliases..."
        echo 'alias pbcopy="wl-copy"' >> "$HOME/.zshrc"
        echo 'alias pbpaste="wl-paste"' >> "$HOME/.zshrc"
    fi

    if [ "$SHELL" != "$(which zsh)" ]; then
        echo "  Setting Zsh as default shell..."
        chsh -s "$(which zsh)"
    fi
}

# --- xremap ---

# The xremap-gnome package owns the `xremap` alternatives symlink, so the config
# and unit below just call `xremap`. It also ships the uinput udev rule itself,
# so only the group and module need setting up here.
setup_xremap() {
    echo ""
    echo "Setting up xremap config..."
    link_config "$DOTFILES_DIR/xremap/config.yml" "$HOME/.config/xremap/config.yml"

    echo ""
    echo "Setting up xremap permissions..."

    if ! groups "$USER" | grep -q '\binput\b'; then
        echo "  Adding $USER to input group..."
        sudo gpasswd -a "$USER" input
    else
        echo "  $USER already in input group"
    fi

    if [ ! -f /etc/modules-load.d/uinput.conf ] || ! grep -q '^uinput$' /etc/modules-load.d/uinput.conf; then
        echo "  Configuring uinput module to load at boot..."
        echo uinput | sudo tee /etc/modules-load.d/uinput.conf > /dev/null
    else
        echo "  uinput module already configured"
    fi

    echo ""
    echo "Setting up xremap service..."
    link_config "$DOTFILES_DIR/xremap/xremap.service" "$HOME/.config/systemd/user/xremap.service"

    systemctl --user daemon-reload
    systemctl --user enable xremap
    systemctl --user restart xremap
    echo "  xremap service enabled and started"
}

# --- Wallpaper ---

# Copies the wallpaper into place; the caller points GNOME at it.
set_wallpaper_file() {
    echo "  Copying wallpaper..."
    cp "$DOTFILES_DIR/wallpaper.jpg" "$HOME/.config/background"
}

# --- Cleanup ---

cleanup() {
    echo ""
    echo "Cleaning up..."
    sudo dnf autoremove -y
    sudo dnf clean all
}

prompt_reboot() {
    echo ""
    echo "Done!"

    local reboot_choice
    read -rp "Reboot now? [y/N] " reboot_choice
    if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
        sudo reboot
    fi
}
