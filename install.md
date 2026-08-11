## Installed
git
stow
ghostty
firefox
yazi ffmpeg 7zip jq poppler fd ripgrep fzf zoxide resvg imagemagick
code
ttf-jetbrains-mono-nerd ttf-noto-nerd




## Removed
foot


## Extra
Had to set locale manually and restart
localectl set-locale LANG=es_ES.UTF-8 LC_MESSAGES=en_US.UTF-8

Had to add --unsupported-gpu flag in
nano /usr/share/wayland-sessions/sway.desktop

For configuring gnome-keyring, had to uncomment corresponding lines in:
sudo nano /etc/pam.d/ly
