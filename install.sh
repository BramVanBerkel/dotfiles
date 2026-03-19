#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

run_quiet() {
    local tmpfile exit_code line_count
    tmpfile=$(mktemp)

    set +e
    "$@" 2>&1 | tee "$tmpfile"
    exit_code=${PIPESTATUS[0]}
    set -e

    line_count=$(wc -l < "$tmpfile")
    rm -f "$tmpfile"

    if [ "$exit_code" -eq 0 ]; then
        for ((i=0; i<line_count; i++)); do
            printf '\033[A\033[2K'
        done
    fi

    return "$exit_code"
}

echo "Installing dotfiles from $DOTFILES_DIR"

# --- Hostname ---
echo ""
echo "Setting hostname..."
if [ "$(hostnamectl hostname)" != "fedora" ]; then
    sudo hostnamectl set-hostname fedora
    echo "  Hostname set to fedora"
else
    echo "  Hostname already set"
fi

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
run_quiet sudo dnf update --refresh -y

echo "  Updating firmware..."
run_quiet sudo fwupdmgr refresh --force || true
run_quiet sudo fwupdmgr update -y || true

# --- Repositories ---
echo ""
echo "Setting up repositories..."

# RPM Fusion (free + nonfree)
if ! rpm -q rpmfusion-free-release &>/dev/null || ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
    echo "  Enabling RPM Fusion (free + nonfree)..."
    run_quiet sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
else
    echo "  RPM Fusion already enabled"
fi

# Cisco OpenH264
echo "  Enabling Cisco OpenH264 repo..."
run_quiet sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1

# COPR repos
COPR_REPOS=(
    "blakegardner/xremap"
)

for repo in "${COPR_REPOS[@]}"; do
    if ! dnf copr list --enabled 2>/dev/null | grep -q "$repo"; then
        echo "  Enabling COPR repo $repo..."
        run_quiet sudo dnf copr enable -y "$repo"
    else
        echo "  COPR $repo already enabled"
    fi
done

# --- Remove bloat ---
echo ""
echo "Removing LibreOffice..."
if rpm -qa | grep -q libreoffice; then
    run_quiet sudo dnf remove -y "libreoffice*"
else
    echo "  LibreOffice already removed"
fi

# --- DNF Packages ---
echo ""
echo "Installing DNF packages..."

# Media codecs
echo "  Installing multimedia codecs..."
if rpm -q ffmpeg-free &>/dev/null; then
    run_quiet sudo dnf swap ffmpeg-free ffmpeg --allowerasing -y
else
    echo "  ffmpeg already swapped"
fi
run_quiet sudo dnf group upgrade multimedia --exclude=PackageKit-gstreamer-plugin -y

DNF_PACKAGES=(
    pipx
    xremap-gnome
    zsh
)

NVIDIA_PACKAGES=(
    akmod-nvidia
    xorg-x11-drv-nvidia
    xorg-x11-drv-nvidia-cuda
)

install_nvidia=false
read -rp "Install NVIDIA drivers? [y/N] " nvidia_choice
if [[ "$nvidia_choice" =~ ^[Yy]$ ]]; then
    install_nvidia=true
    DNF_PACKAGES+=("${NVIDIA_PACKAGES[@]}")
    read -rp "GPU power limit in watts? [200] " gpu_power_limit
    gpu_power_limit=${gpu_power_limit:-200}
fi

for pkg in "${DNF_PACKAGES[@]}"; do
    if ! rpm -q "$pkg" &>/dev/null; then
        echo "  Installing $pkg..."
        run_quiet sudo dnf install -y "$pkg"
    else
        echo "  $pkg already installed"
    fi
done

# --- GPU power limit service ---
if [[ "$install_nvidia" == true ]]; then
    echo ""
    echo "Setting up GPU power limit service (${gpu_power_limit}W)..."
    cat <<EOF | sudo tee /etc/systemd/system/gpu-power-limit.service > /dev/null
[Unit]
Description=GPU power limiter
After=network.target

[Service]
User=root
Type=oneshot
Restart=never
RemainAfterExit=yes
ExecStart=/usr/bin/bash -c "nvidia-smi -pl ${gpu_power_limit}"

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable gpu-power-limit.service
    echo "  gpu-power-limit.service installed and enabled"
fi

# --- Flatpaks ---
echo ""
echo "Setting up Flatpak..."

echo "  Enabling Flathub..."
run_quiet flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "Installing Flatpaks..."

FLATPAKS=(
    com.bitwarden.desktop
    com.spotify.Client
    com.valvesoftware.Steam
    it.mijorus.gearlever
    net.nokyan.Resources
    com.mattjakeman.ExtensionManager
)

for app in "${FLATPAKS[@]}"; do
    if ! flatpak info "$app" &>/dev/null; then
        echo "  Installing $app..."
        run_quiet flatpak install -y flathub "$app"
    else
        echo "  $app already installed"
    fi
done

# Jagex Launcher (installed from custom repo)
if ! flatpak info com.jagexlauncher.JagexLauncher &>/dev/null; then
    echo "  Installing Jagex Launcher..."
    run_quiet bash -c 'curl -fSsL https://raw.githubusercontent.com/nmlynch94/com.jagexlauncher.JagexLauncher/main/install-jagex-launcher-repo.sh | bash'
else
    echo "  Jagex Launcher already installed"
fi

# --- AppImages ---
echo ""
echo "Installing AppImages..."

mkdir -p "$HOME/Applications"

# Helium Browser
if ! flatpak run it.mijorus.gearlever --list-installed 2>/dev/null | grep -qi helium; then
    echo "  Installing Helium Browser..."
    HELIUM_VERSION=$(curl -fSs https://api.github.com/repos/imputnet/helium-linux/releases/latest | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
    HELIUM_URL="https://github.com/imputnet/helium-linux/releases/download/${HELIUM_VERSION}/helium-${HELIUM_VERSION}-x86_64.AppImage"
    HELIUM_FILE="$HOME/Applications/helium-${HELIUM_VERSION}-x86_64.AppImage"
    curl -fSL -o "$HELIUM_FILE" "$HELIUM_URL"
    chmod +x "$HELIUM_FILE"
    flatpak run it.mijorus.gearlever --integrate "$HELIUM_FILE"
else
    echo "  Helium Browser already installed"
fi

echo "  Setting Helium as default browser..."
xdg-settings set default-web-browser helium.desktop

# --- Zed ---
echo ""
echo "Installing Zed editor..."

if [ ! -d "$HOME/.local/zed.app" ]; then
    curl -f https://zed.dev/install.sh | sh
else
    echo "  Zed already installed"
fi

# --- Zsh ---
echo ""
echo "Setting up Zsh..."

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "  Installing Oh My Zsh..."
    run_quiet sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

if grep -q '^# export PATH=$HOME/bin:$HOME/.local/bin' "$HOME/.zshrc" 2>/dev/null; then
    echo "  Uncommenting PATH export..."
    sed -i 's/^# export PATH=$HOME\/bin:$HOME\/.local\/bin/export PATH=$HOME\/bin:$HOME\/.local\/bin/' "$HOME/.zshrc"
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

# --- xremap permissions ---
echo ""
echo "Setting up xremap permissions..."

UDEV_RULE='KERNEL=="uinput", GROUP="input", TAG+="uaccess"'
UDEV_FILE="/etc/udev/rules.d/input.rules"

if [ ! -f "$UDEV_FILE" ] || ! grep -qF "$UDEV_RULE" "$UDEV_FILE"; then
    echo "  Adding udev rule for uinput..."
    echo "$UDEV_RULE" | sudo tee "$UDEV_FILE" > /dev/null
else
    echo "  Udev rule already configured"
fi

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

# --- xremap service ---
echo ""
echo "Setting up xremap service..."

SERVICE_DIR="$HOME/.local/share/systemd/user"
SERVICE_SRC="$DOTFILES_DIR/xremap/xremap.service"
SERVICE_DEST="$SERVICE_DIR/xremap.service"

mkdir -p "$SERVICE_DIR"

if [ -e "$SERVICE_DEST" ] && [ ! -L "$SERVICE_DEST" ]; then
    echo "  Backing up existing $SERVICE_DEST to ${SERVICE_DEST}.bak"
    mv "$SERVICE_DEST" "${SERVICE_DEST}.bak"
fi

ln -sf "$SERVICE_SRC" "$SERVICE_DEST"
echo "  Linked $SERVICE_DEST -> $SERVICE_SRC"

systemctl --user daemon-reload
systemctl --user enable xremap
systemctl --user start xremap
echo "  xremap service enabled and started"

# --- GNOME extensions ---
echo ""
echo "Installing GNOME extensions..."

if ! command -v gext &>/dev/null; then
    echo "  Installing gnome-extensions-cli..."
    run_quiet pipx install gnome-extensions-cli
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
        run_quiet gext install "$ext"
    else
        echo "  $ext already installed"
    fi
    run_quiet gext enable "$ext"
done

echo "  Disabling background logo..."
gnome-extensions disable "background-logo@fedorahosted.org" 2>/dev/null || true

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

echo "  Showing seconds on clock..."
gsettings set org.gnome.desktop.interface clock-show-seconds true

echo "  Enabling dark mode..."
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

echo "  Setting window switcher shortcut to Ctrl+Tab..."
gsettings set org.gnome.desktop.wm.keybindings switch-windows "['<Super>Tab']"

echo "  Setting pinned apps..."
gsettings set org.gnome.shell favorite-apps "['helium.desktop', 'org.gnome.Ptyxis.desktop', 'org.gnome.Nautilus.desktop', 'dev.zed.Zed.desktop', 'com.jagexlauncher.JagexLauncher.desktop', 'com.valvesoftware.Steam.desktop']"

echo "  Setting formats to Dutch..."
gsettings set org.gnome.system.locale region 'nl_NL.UTF-8'

echo "  Setting wallpaper..."
cp "$DOTFILES_DIR/wallpaper.jpg" "$HOME/.config/background"
gsettings set org.gnome.desktop.background picture-uri "file://$HOME/.config/background"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$HOME/.config/background"

# --- Cleanup ---
echo ""
echo "Cleaning up..."
run_quiet sudo dnf autoremove -y
run_quiet sudo dnf clean all

echo ""
echo "Done!"

read -rp "Reboot now? [y/N] " reboot_choice
if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
    sudo reboot
fi
