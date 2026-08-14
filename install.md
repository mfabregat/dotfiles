## Installed
git
stow
ghostty
firefox
yazi ffmpeg 7zip jq poppler fd ripgrep fzf zoxide resvg imagemagick
code
ttf-jetbrains-mono-nerd ttf-noto-nerd
gnome-keyring
base-devel
flatpak
autotiling
shikane



## Quickshell shell (right bar · launcher · notifications · OSD · polkit)

```bash
sudo pacman -S quickshell pipewire brightnessctl polkit networkmanager upower swayidle wl-clipboard grim
```

- `swayidle` (idle → lock → DPMS off; autostarted by the sway config).

- `quickshell` is pre-1.0: **pin 0.3.0** (Arch `extra/quickshell`); do not
  upgrade blindly — configs live in git (see PLAN-quickshell.md).
- `pipewire` provides wpctl (media/brightness keybindings); `brightnessctl`
  is only needed for brightness *writes* (reads are native sysfs).
- `networkmanager` (bar network state), `upower` (battery), `polkit` (auth
  agent), `wl-clipboard` (phase-7 clipboard manager), `grim` (screenshots).
- Sway ≥ 1.8 required (ext-session-lock for the phase-6 lock screen).




## Removed
foot


## Extra
Had to set locale manually and restart
localectl set-locale LANG=es_ES.UTF-8 LC_MESSAGES=en_US.UTF-8

Had to add --unsupported-gpu flag in
nano /usr/share/wayland-sessions/sway.desktop

For configuring gnome-keyring, had to uncomment corresponding lines in:
sudo nano /etc/pam.d/ly


For configuring dark theme globally:
I've only done the first one so far, when I see it's necessery I'll do the rest.
```bash
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
mkdir -p ~/.config/gtk-3.0
cat <<EOF > ~/.config/gtk-3.0/settings.ini
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita-dark
EOF
```

### Spotify
Going to test spotify-player