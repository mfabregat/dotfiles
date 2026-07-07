sudo apt update && sudo apt upgrade

# Remove unattended-upgrades
sudo apt remove unattended-upgrades


### Browsers
# Remove snap firefox and install apt version
sudo snap remove firefox
sudo add-apt-repository ppa:mozillateam/ppa
echo '
Package: *
Pin: release o=LP-PPA-mozillateam
Pin-Priority: 1001
' | sudo tee /etc/apt/preferences.d/mozilla-firefox
sudo apt install firefox
# Install Brave
sudo apt install curl
curl -fsS https://dl.brave.com/install.sh | sh


# Clone dotfiles
sudo apt install git stow
git config --global user.name "Marc Fabregat"
git config --global user.email "marcfj98@gmail.com"
ssh-keygen -t ed25519 -C "marcfj98@gmail.com"
cat ~/.ssh/id_ed25519.pub
# Add it to GitHub
git clone git@github.com:mfabregat/dotfiles.git ~/dotfiles
cd ~/dotfiles

# Apply Ubuntu and GNOME configs


# Download apt version of code https://code.visualstudio.com/docs/setup/linux
sudo apt install ~/Downloads/code*.deb

# Install docker
wget -q -O - https://get.docker.com | sudo bash
sudo usermod -aG docker $USER
# To activate in current session
newgrp docker

# Check if NVIDIA drivers have been automatically installed
nvidia-smi
# If not
sudo ubuntu-drivers install

# Install Ghostty
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)"
stow ghostty

# Install Joplin
wget -O - https://raw.githubusercontent.com/laurent22/joplin/dev/Joplin_install_and_update.sh | bash
# Key ID: euGDAmN1GJduRjfvfHxnCFB4Azd3sx98
# Secret Key: yyDN4p73mKMZcTIHQ7qUbH3uNCMvpOtv


### Entertainment
# Spotify
curl -sS https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.asc | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
echo "deb https://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list
sudo apt-get update && sudo apt-get install spotify-client
# Spicetify
curl -fsSL https://raw.githubusercontent.com/spicetify/cli/main/install.sh | sh
sudo chmod a+wr /usr/share/spotify && sudo chmod a+wr /usr/share/spotify/Apps -R
# bash && spicetify backup apply
# curl -fsSL https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh | sh
cd ~/dotfiles
stow spicetify
spicetify config current_theme text && spicetify config color_scheme Gruvbox && spicetify backup apply


# Steam
# Download from https://store.steampowered.com/about/download
sudo apt install ~/Downloads/steam*.deb

# Discord (testing Vesktop)
sudo apt install flatpak
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
# or manually download the .deb from https://vesktop.dev/install/linux/
sudo apt install ~/Downloads/vesktop*.deb

# Faugus
sudo dpkg --add-architecture i386
sudo add-apt-repository -y ppa:faugus/faugus-launcher
sudo apt update
sudo apt install -y faugus-launcher

# Stremio
flatpak install flathub com.stremio.Stremio


## Themes
# https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme/tree/master
sudo apt install gnome-tweaks
sudo apt install gtk2-engines-murrine
# Move downloaded folder (the one with gtk-4.0) to ~/.themes
cd ~/dotfiles
stow gruvbox_gtk
# Then open gnome-tweaks and select the theme
# Finally copy only assets, gtk.css and gtk-dark.css to ~/.config/gtk-4.0
sudo flatpak override --filesystem=$HOME/.themes
sudo flatpak override --filesystem=$HOME/.icons
flatpak override --user --filesystem=xdg-config/gtk-4.0
sudo flatpak override --filesystem=xdg-config/gtk-4.0
ln -s ~/.themes/Gruvbox-BL-MB-Dark ~/.local/share/themes/Gruvbox-BL-MB-Dark # is this necessary?