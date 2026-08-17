# Dotfiles

Fedora setup scripts. Pick the one matching your desktop:

- GNOME (Fedora Workstation): `./install-gnome.sh`
- KDE Plasma (Fedora KDE): `./install-kde.sh`

Both source `common.sh`, which holds everything that isn't desktop-specific.

After arranging the Plasma panel and shortcuts by hand, run `kde/export-config.sh`
to copy that config back into the repo so `install-kde.sh` can restore it later.

## Checklist

### System (shared)
- [ ] Hostname set to `fedora`
- [ ] DNF `max_parallel_downloads=10` configured
- [ ] System packages updated (`dnf upgrade`)
- [ ] Firmware updated (`fwupdmgr`)

### Repositories (shared)
- [ ] RPM Fusion (free + nonfree) enabled
- [ ] Cisco OpenH264 repo enabled
- [ ] COPR `blakegardner/xremap` enabled

### Packages (shared)
- [ ] LibreOffice removed
- [ ] Multimedia codecs installed (ffmpeg, GStreamer plugins)
- [ ] `steam` installed
- [ ] `wl-clipboard` installed
- [ ] `zsh` installed

### NVIDIA (optional, shared)
- [ ] `akmod-nvidia` installed
- [ ] `xorg-x11-drv-nvidia` installed
- [ ] `xorg-x11-drv-nvidia-cuda` installed
- [ ] GPU power limit service installed and enabled (`systemctl status gpu-power-limit.service`)

### Flatpaks (shared)
- [ ] Flathub remote enabled
- [ ] Bitwarden (`com.bitwarden.desktop`)
- [ ] Spotify (`com.spotify.Client`)
- [ ] Gear Lever (`it.mijorus.gearlever`)
- [ ] Jagex Launcher (`com.jagexlauncher.JagexLauncher`)

### Apps (shared)
- [ ] Zen Browser installed and integrated via Gear Lever
- [ ] Zen set as default browser
- [ ] Zed editor installed (`~/.local/zed.app`)

### Zsh (shared)
- [ ] Oh My Zsh installed (`~/.oh-my-zsh`)
- [ ] `PATH` export uncommented in `.zshrc`
- [ ] `alias open="xdg-open"` added to `.zshrc`
- [ ] `pbcopy`/`pbpaste` aliases added to `.zshrc`
- [ ] Zsh set as default shell

### xremap (shared)
- [ ] `xremap-gnome` (GNOME) or `xremap-kde` (KDE) installed — they conflict, never both
- [ ] Config symlinked to `~/.config/xremap/config.yml`
- [ ] User added to `input` group
- [ ] `uinput` module configured to load at boot
- [ ] `xremap.service` symlinked to `~/.config/systemd/user/`
- [ ] xremap service enabled and running (`systemctl --user status xremap`)

The uinput udev rule ships with the xremap package (`/usr/lib/udev/rules.d/00-xremap-input.rules`),
so the scripts don't write one.

## GNOME

### Packages
- [ ] GNOME System Monitor removed (replaced by Resources)
- [ ] `pipx` installed (for `gext`)

### Flatpaks
- [ ] Resources (`net.nokyan.Resources`)
- [ ] Extension Manager (`com.mattjakeman.ExtensionManager`)

### Extensions
- [ ] `gnome-extensions-cli` (`gext`) installed via pipx
- [ ] Dash to Panel installed and enabled
- [ ] AppIndicator Support installed and enabled
- [ ] ddterm installed and enabled
- [ ] xremap extension installed and enabled
- [ ] Background logo extension disabled
- [ ] Dash to Panel config restored

### Settings
- [ ] Minimize and maximize buttons enabled
- [ ] Mouse speed set to -0.23, acceleration disabled
- [ ] Clock shows seconds
- [ ] Dark mode enabled
- [ ] Window switcher shortcut set to Ctrl+Tab
- [ ] Taskbar pinned apps set
- [ ] Locale/formats set to Dutch (`nl_NL.UTF-8`)
- [ ] Wallpaper set

## KDE Plasma

### Packages
- [ ] `ptyxis` installed (not shipped by Fedora KDE)
- [ ] `yakuake` installed (drop-down terminal, replaces ddterm)
- [ ] Yakuake autostart enabled (`~/.config/autostart/`)

Native `plasma-systemmonitor` is kept, so no Resources flatpak here.

### Settings
- [ ] Mouse speed set to -0.230, flat acceleration (per device, in `kcminputrc`)
- [ ] Window switcher shortcut set to Ctrl+Tab
- [ ] KRunner shortcut set to Ctrl+Space
- [ ] Locale/formats set to Dutch (`nl_NL.UTF-8`)
- [ ] Dark mode enabled (Breeze Dark)
- [ ] Wallpaper set
- [ ] Panel layout, pinned apps and clock seconds restored from `kde/plasma-org.kde.plasma.desktop-appletsrc`
- [ ] Global shortcuts restored from `kde/kglobalshortcutsrc`

Minimize/maximize buttons need no setting — Breeze shows them by default.
