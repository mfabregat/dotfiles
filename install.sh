sudo apt update && sudo apt upgrade

# Remove unattended-upgrades
sudo apt remove unattended-upgrades

# Remove Ubuntu dockqq
gnome-extensions disable ubuntu-dock@ubuntu.com

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
# Not showing in Desktop apps?
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
git clone git@github.com:mfabregat/dotfiles.git

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


### Entertainment
# Spotify
curl -sS https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.asc | sudo gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/spotify.gpg
echo "deb https://repository.spotify.com stable non-free" | sudo tee /etc/apt/sources.list.d/spotify.list
sudo apt-get update && sudo apt-get install spotify-client

