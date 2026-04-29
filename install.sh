#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- OS Detection ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        fedora) OS="fedora" ;;
        ubuntu) OS="ubuntu" ;;
        *) echo "Unsupported OS: $ID" >&2; exit 1 ;;
    esac
else
    echo "Cannot detect OS: /etc/os-release not found" >&2
    exit 1
fi

# --- Package management helpers ---
pkg_installed() {
    case "$OS" in
        fedora) rpm -q "$1" &>/dev/null ;;
        ubuntu) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed" ;;
    esac
}

pkg_install() {
    case "$OS" in
        fedora) run_quiet sudo dnf install -y "$@" ;;
        ubuntu) run_quiet sudo apt install -y "$@" ;;
    esac
}

pkg_remove() {
    case "$OS" in
        fedora) run_quiet sudo dnf remove -y "$@" ;;
        ubuntu) run_quiet sudo apt remove -y "$@" ;;
    esac
}

pkg_update() {
    case "$OS" in
        fedora) run_quiet sudo dnf update --refresh -y ;;
        ubuntu) run_quiet sudo apt update && run_quiet sudo apt upgrade -y ;;
    esac
}

pkg_cleanup() {
    case "$OS" in
        fedora) run_quiet sudo dnf autoremove -y && run_quiet sudo dnf clean all ;;
        ubuntu) run_quiet sudo apt autoremove -y && run_quiet sudo apt clean ;;
    esac
}

run_quiet() {
    local exit_code

    tput sc  # save cursor position

    set +e
    local cmd=""
    for arg in "$@"; do
        cmd+="'${arg//\'/\'\\\'\'}' "
    done
    script -qe -c "$cmd" /dev/null
    exit_code=$?
    set -e

    if [ "$exit_code" -eq 0 ]; then
        tput rc  # restore cursor position
        tput ed  # erase to end of display
    fi

    return "$exit_code"
}

echo "Installing dotfiles from $DOTFILES_DIR"

# --- Dependencies ---
if ! command -v script &>/dev/null; then
    echo "Installing script dependency..."
    case "$OS" in
        fedora) sudo dnf install -y util-linux-script > /dev/null ;;
        ubuntu) sudo apt install -y bsdutils > /dev/null ;;
    esac
fi

# --- Hostname ---
echo ""
echo "Setting hostname..."
if [ "$(hostnamectl hostname)" != "fedora" ]; then
    sudo hostnamectl set-hostname fedora
    echo "  Hostname set to fedora"
else
    echo "  Hostname already set"
fi

# --- Package manager configuration ---
echo ""
case "$OS" in
    fedora)
        echo "Optimizing DNF configuration..."
        if ! grep -q "max_parallel_downloads" /etc/dnf/dnf.conf 2>/dev/null; then
            echo "  Setting max_parallel_downloads=10..."
            echo "max_parallel_downloads=10" | sudo tee -a /etc/dnf/dnf.conf > /dev/null
        else
            echo "  max_parallel_downloads already configured"
        fi
        ;;
    ubuntu)
        echo "Updating apt package index..."
        run_quiet sudo apt update
        ;;
esac

echo "  Updating system..."
pkg_update

echo "  Updating firmware..."
run_quiet sudo fwupdmgr refresh --force || true
run_quiet sudo fwupdmgr update -y || true

# --- Repositories ---
echo ""
echo "Setting up repositories..."

case "$OS" in
    fedora)
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
        ;;
    ubuntu)
        if ! command -v add-apt-repository &>/dev/null; then
            run_quiet sudo apt install -y software-properties-common
        fi
        echo "  Enabling universe and multiverse repositories..."
        run_quiet sudo add-apt-repository -y universe
        run_quiet sudo add-apt-repository -y multiverse
        echo "  Enabling i386 architecture for Steam..."
        sudo dpkg --add-architecture i386
        run_quiet sudo apt update
        ;;
esac

# --- Remove bloat ---
echo ""
echo "Removing LibreOffice..."
libreoffice_present=false
case "$OS" in
    fedora) rpm -qa | grep -q libreoffice && libreoffice_present=true || true ;;
    ubuntu) dpkg -l 2>/dev/null | grep -q "^ii.*libreoffice" && libreoffice_present=true || true ;;
esac

if $libreoffice_present; then
    pkg_remove "libreoffice*"
else
    echo "  LibreOffice already removed"
fi

# --- Packages ---
echo ""
echo "Installing packages..."

# Multimedia codecs
echo "  Installing multimedia codecs..."
case "$OS" in
    fedora)
        if rpm -q ffmpeg-free &>/dev/null; then
            run_quiet sudo dnf swap ffmpeg-free ffmpeg --allowerasing -y
        else
            echo "  ffmpeg already swapped"
        fi
        run_quiet sudo dnf group upgrade multimedia --exclude=PackageKit-gstreamer-plugin -y
        ;;
    ubuntu)
        run_quiet sudo apt install -y \
            ffmpeg \
            gstreamer1.0-plugins-bad \
            gstreamer1.0-plugins-ugly \
            gstreamer1.0-libav \
            libavcodec-extra
        ;;
esac

# Package list (xremap installed separately on Ubuntu via binary below)
case "$OS" in
    fedora)
        PACKAGES=(
            pipx
            steam
            util-linux-script
            xremap-gnome
            zsh
        )
        ;;
    ubuntu)
        PACKAGES=(
            pipx
            steam
            unzip
            zsh
        )
        ;;
esac

# NVIDIA
install_nvidia=false
read -rp "Install NVIDIA drivers? [y/N] " nvidia_choice
if [[ "$nvidia_choice" =~ ^[Yy]$ ]]; then
    install_nvidia=true
    read -rp "GPU power limit in watts? [200] " gpu_power_limit
    gpu_power_limit=${gpu_power_limit:-200}
    case "$OS" in
        fedora) PACKAGES+=(akmod-nvidia xorg-x11-drv-nvidia xorg-x11-drv-nvidia-cuda) ;;
    esac
fi

MISSING=()
for pkg in "${PACKAGES[@]}"; do
    if ! pkg_installed "$pkg"; then
        MISSING+=("$pkg")
    else
        echo "  $pkg already installed"
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "  Installing ${MISSING[*]}..."
    pkg_install "${MISSING[@]}"
fi

# Ubuntu: NVIDIA via ubuntu-drivers (handled separately from package list)
if [[ "$install_nvidia" == true && "$OS" == "ubuntu" ]]; then
    echo "  Installing NVIDIA drivers..."
    if ! command -v ubuntu-drivers &>/dev/null; then
        run_quiet sudo apt install -y ubuntu-drivers-common
    fi
    run_quiet sudo ubuntu-drivers autoinstall
fi

# Ubuntu: install xremap binary from GitHub (Fedora gets it from the xremap-gnome COPR package)
if [[ "$OS" == "ubuntu" ]]; then
    echo ""
    echo "Installing xremap..."
    if ! command -v xremap &>/dev/null; then
        xremap_version=$(curl -fSs https://api.github.com/repos/xremap/xremap/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
        curl -fSL "https://github.com/xremap/xremap/releases/download/${xremap_version}/xremap-linux-x86_64-gnome.zip" -o /tmp/xremap.zip
        unzip -o /tmp/xremap.zip -d /tmp/xremap-extract
        sudo install -m 755 /tmp/xremap-extract/xremap /usr/local/bin/xremap
        rm -rf /tmp/xremap.zip /tmp/xremap-extract
        echo "  xremap installed"
    else
        echo "  xremap already installed"
    fi
fi

# --- GPU power limit service ---
if [[ "$install_nvidia" == true ]]; then
    echo ""
    echo "Setting up GPU power limit service (${gpu_power_limit}W)..."
    cat <<EOF | sudo tee /etc/systemd/system/gpu-power-limit.service > /dev/null
[Unit]
Description=GPU power limiter
After=nvidia-persistenced.service

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

# Ubuntu doesn't ship Flatpak by default
if [[ "$OS" == "ubuntu" ]] && ! command -v flatpak &>/dev/null; then
    echo "  Installing Flatpak..."
    run_quiet sudo apt install -y flatpak
fi

echo "  Enabling Flathub..."
run_quiet flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "Installing Flatpaks..."

FLATPAKS=(
    com.bitwarden.desktop
    com.spotify.Client
    it.mijorus.gearlever
    net.nokyan.Resources
    com.mattjakeman.ExtensionManager
)

MISSING_FLATPAKS=()
for app in "${FLATPAKS[@]}"; do
    if ! flatpak info "$app" &>/dev/null; then
        MISSING_FLATPAKS+=("$app")
    else
        echo "  $app already installed"
    fi
done

if [ ${#MISSING_FLATPAKS[@]} -gt 0 ]; then
    echo "  Installing ${MISSING_FLATPAKS[*]}..."
    run_quiet flatpak install -y flathub "${MISSING_FLATPAKS[@]}"
fi

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

# Zen Browser
if ! flatpak run it.mijorus.gearlever --list-installed 2>/dev/null | grep -qi zen; then
    echo "  Installing Zen Browser..."
    ZEN_VERSION=$(curl -fSs https://api.github.com/repos/zen-browser/desktop/releases/latest | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
    ZEN_URL="https://github.com/zen-browser/desktop/releases/download/${ZEN_VERSION}/zen-x86_64.AppImage"
    ZEN_FILE="$HOME/Applications/zen-x86_64.AppImage"
    curl -fSL -o "$ZEN_FILE" "$ZEN_URL"
    chmod +x "$ZEN_FILE"
    flatpak run it.mijorus.gearlever --integrate "$ZEN_FILE"
else
    echo "  Zen Browser already installed"
fi

echo "  Setting Zen as default browser..."
xdg-settings set default-web-browser zen.desktop

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
gsettings set org.gnome.shell favorite-apps "['zen.desktop', 'org.gnome.Ptyxis.desktop', 'org.gnome.Nautilus.desktop', 'dev.zed.Zed.desktop', 'com.jagexlauncher.JagexLauncher.desktop', 'com.valvesoftware.Steam.desktop']"

echo "  Setting formats to Dutch..."
gsettings set org.gnome.system.locale region 'nl_NL.UTF-8'

echo "  Setting wallpaper..."
cp "$DOTFILES_DIR/wallpaper.jpg" "$HOME/.config/background"
gsettings set org.gnome.desktop.background picture-uri "file://$HOME/.config/background"
gsettings set org.gnome.desktop.background picture-uri-dark "file://$HOME/.config/background"

# --- Cleanup ---
echo ""
echo "Cleaning up..."
pkg_cleanup

echo ""
echo "Done!"

read -rp "Reboot now? [y/N] " reboot_choice
if [[ "$reboot_choice" =~ ^[Yy]$ ]]; then
    sudo reboot
fi
