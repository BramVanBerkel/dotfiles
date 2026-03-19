# Dotfiles

Fedora setup script. Run with `./install.sh`.

## Checklist

### System
- [ ] Hostname set to `fedora`
- [ ] DNF `max_parallel_downloads=10` configured
- [ ] System packages updated (`dnf upgrade`)
- [ ] Firmware updated (`fwupdmgr`)

### Repositories
- [ ] RPM Fusion (free + nonfree) enabled
- [ ] Cisco OpenH264 repo enabled
- [ ] COPR `blakegardner/xremap` enabled

### Packages
- [ ] LibreOffice removed
- [ ] Multimedia codecs installed (ffmpeg, GStreamer plugins)
- [ ] `pipx` installed
- [ ] `xremap-gnome` installed
- [ ] `zsh` installed

### NVIDIA (optional)
- [ ] `akmod-nvidia` installed
- [ ] `xorg-x11-drv-nvidia` installed
- [ ] `xorg-x11-drv-nvidia-cuda` installed
- [ ] GPU power limit service installed and enabled (`systemctl status gpu-power-limit.service`)

### Flatpaks
- [ ] Flathub remote enabled
- [ ] Bitwarden (`com.bitwarden.desktop`)
- [ ] Spotify (`com.spotify.Client`)
- [ ] Steam (`com.valvesoftware.Steam`)
- [ ] Gear Lever (`it.mijorus.gearlever`)
- [ ] Resources (`net.nokyan.Resources`)
- [ ] Extension Manager (`com.mattjakeman.ExtensionManager`)
- [ ] Jagex Launcher (`com.jagexlauncher.JagexLauncher`)

### AppImages
- [ ] Helium Browser installed and integrated via Gear Lever
- [ ] Helium set as default browser

### Zed
- [ ] Zed editor installed (`~/.local/zed.app`)

### Zsh
- [ ] Oh My Zsh installed (`~/.oh-my-zsh`)
- [ ] `PATH` export uncommented in `.zshrc`
- [ ] `alias open="xdg-open"` added to `.zshrc`
- [ ] Zsh set as default shell

### xremap
- [ ] Config symlinked to `~/.config/xremap/config.yml`
- [ ] udev rule created (`/etc/udev/rules.d/input.rules`)
- [ ] User added to `input` group
- [ ] `uinput` module configured to load at boot
- [ ] `xremap.service` symlinked to `~/.local/share/systemd/user/`
- [ ] xremap service enabled and running (`systemctl --user status xremap`)

### GNOME extensions
- [ ] `gnome-extensions-cli` (`gext`) installed via pipx
- [ ] Dash to Panel installed and enabled
- [ ] AppIndicator Support installed and enabled
- [ ] Search Light installed and enabled
- [ ] ddterm installed and enabled
- [ ] xremap extension installed and enabled
- [ ] Background logo extension disabled
- [ ] Dash to Panel config restored
- [ ] Search Light config restored

### GNOME settings
- [ ] Minimize and maximize buttons enabled
- [ ] Mouse speed set to -0.23, acceleration disabled
- [ ] Clock shows seconds
- [ ] Dark mode enabled
- [ ] Taskbar pinned apps set
- [ ] Locale/formats set to Dutch (`nl_NL.UTF-8`)
- [ ] Wallpaper set
