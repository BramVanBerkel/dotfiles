# Dotfiles

Fedora Workstation (GNOME) setup script: `./install.sh`

It sources `lib.sh`, which holds the implementation of each step.

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
- [ ] GNOME System Monitor removed (replaced by Resources)
- [ ] Multimedia codecs installed (ffmpeg, GStreamer plugins)
- [ ] `pipx` installed (for `gext`)
- [ ] `steam` installed
- [ ] `wl-clipboard` installed
- [ ] `zsh` installed

### NVIDIA (optional)
- [ ] `akmod-nvidia` installed
- [ ] `xorg-x11-drv-nvidia` installed
- [ ] `xorg-x11-drv-nvidia-cuda` installed
- [ ] GPU power limit service installed and enabled (`systemctl status gpu-power-limit.service`)

### Flatpaks
- [ ] Flathub remote enabled
- [ ] Bolt Launcher (`com.adamcake.Bolt`)
- [ ] Bitwarden (`com.bitwarden.desktop`)
- [ ] Spotify (`com.spotify.Client`)
- [ ] Gear Lever (`it.mijorus.gearlever`)
- [ ] Resources (`net.nokyan.Resources`)
- [ ] Extension Manager (`com.mattjakeman.ExtensionManager`)

### Apps
- [ ] Zen Browser installed and integrated via Gear Lever
- [ ] Zen set as default browser
- [ ] Zed editor installed (`~/.local/zed.app`)

### Zsh
- [ ] Oh My Zsh installed (`~/.oh-my-zsh`)
- [ ] `PATH` export uncommented in `.zshrc`
- [ ] `alias open="xdg-open"` added to `.zshrc`
- [ ] `pbcopy`/`pbpaste` aliases added to `.zshrc`
- [ ] Zsh set as default shell

### xremap
- [ ] `xremap-gnome` installed
- [ ] Config symlinked to `~/.config/xremap/config.yml`
- [ ] User added to `input` group
- [ ] `uinput` module configured to load at boot
- [ ] `xremap.service` symlinked to `~/.config/systemd/user/`
- [ ] xremap service enabled and running (`systemctl --user status xremap`)

The uinput udev rule ships with the xremap package (`/usr/lib/udev/rules.d/00-xremap-input.rules`),
so the script doesn't write one.

### Extensions
- [ ] `gnome-extensions-cli` (`gext`) installed via pipx
- [ ] Dash to Panel installed and enabled
- [ ] AppIndicator Support installed and enabled
- [ ] ddterm installed and enabled
- [ ] xremap extension installed and enabled
- [ ] Background logo extension disabled
- [ ] Dash to Panel config restored
- [ ] SearchLightNG installed and enabled (`search-light-ng@salix.host`)
- [ ] SearchLightNG config restored (launcher on Ctrl+Space, i.e. ⌘+Space)

SearchLightNG replaces the unmaintained Search Light, which crashed the GNOME 50
session. It isn't on extensions.gnome.org, so it comes from upstream's installer
at <https://git.salix.host/salix/searchlightng> rather than through `gext`.

### Settings
- [ ] Minimize and maximize buttons enabled
- [ ] Mouse speed set to -0.23, acceleration disabled
- [ ] Clock shows seconds
- [ ] Dark mode enabled
- [ ] Window switcher shortcut set to Ctrl+Tab
- [ ] Taskbar pinned apps set
- [ ] Locale/formats set to Dutch (`nl_NL.UTF-8`)
- [ ] Wallpaper set
