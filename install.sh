sudo apt update && sudo apt upgrade

# Clone dotfiles
sudo apt install git stow
git config --global user.name "Marc Fabregat"
git config --global user.email "marcfj98@gmail.com"
git config


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

