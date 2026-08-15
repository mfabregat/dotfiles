sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
sudo dnf install akmod-nvidia

localectl set-locale LANG=es_ES.UTF-8 LC_MESSAGES=en_US.UTF-8

sudo dnf install sway git stow firefox gammastep gnome-keyring python3-pip wget flatpak
git config --global user.name "Marc Fabregat"
git config --global user.email marcfj98@gmail.com
git clone https://github.com/mfabregat/dotfiles
cd dotfiles
stow sway ghostty quickshell gammastep

python -m pip install --user autotiling

sudo dnf copr enable errornointernet/quickshell
sudo dnf install quickshell

sudo dnf copr enable scottames/ghostty
sudo dnf install ghostty

stow code
sudo tee -a /etc/yum.repos.d/vscodium.repo << 'EOF'
[gitlab.com_paulcarroty_vscodium_repo]
name=gitlab.com_paulcarroty_vscodium_repo
baseurl=https://paulcarroty.gitlab.io/vscodium-deb-rpm-repo/rpms/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg
metadata_expire=1h
EOF
sudo dnf install codium

stow helium
sudo dnf copr enable imput/helium
sudo dnf install helium-bin
# Extensions -> Developer mode -> Load unpacked -> ~/.config/net.imput.helium/themes/guvbox-282828

gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

sudo dnf install nodejs npm
curl -fsSL https://pi.dev/install.sh | sh

mkdir -p ~/.local/share/fonts
cd /tmp
curl -OL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz
tar -xf JetBrainsMono.tar.xz
mv JetBrainsMono* ~/.local/share/fonts
curl -OL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Noto.tar.xz
tar -xf Noto.tar.xz
mv Noto* ~/.local/share/fonts
fc-cache -fv

sudo nano /etc/pam.d/login
# Add as the last entry of auth/session:
# auth       optional     pam_gnome_keyring.so
# session    optional     pam_gnome_keyring.so auto_start

wget -q -O - https://get.docker.com | sudo bash
sudo usermod -aG docker $USER

sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install flathub com.spotify.Client

lsblk -f
sudo mkdir -p /mnt/{games,data}
sudo nano /etc/fstab
systemctl daemon-reload
sudo mount -a
