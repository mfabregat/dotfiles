# su -
# apt install sudo
# usermod -aG sudo marc
# newgrp

localectl set-locale LANG=es_ES.UTF-8 LC_MESSAGES=en_US.UTF-8

sudo apt-get update && sudo apt-get upgrade
sudo apt install curl git sway stow firefox-esr flatpak thunar

cd ~ && git clone https://github.com/mfabregat/dotfiles -b debian && cd dotfiles
stow sway bash

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh)"
cd ~/dotfiles && stow ghostty

# Download latest .deb from https://code.visualstudio.com/
sudo apt install ./code*.deb

# Noctalia
wget https://pkg.noctalia.dev/deb/nickh-archive-keyring.deb && sudo dpkg -i nickh-archive-keyring.deb
sudo wget -O /etc/apt/sources.list.d/noctalia-trixie.sources https://pkg.noctalia.dev/deb/noctalia-trixie.sources
sudo apt update
sudo apt install noctalia
cd ~/dotfiles && stow noctalia

flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install flathub com.spotify.Client

# Helium Browser
curl -fsSL https://raw.githubusercontent.com/imputnet/helium-linux/main/pubkey.asc | sudo gpg --dearmor -o /usr/share/keyrings/helium.gpg
echo "deb [signed-by=/usr/share/keyrings/helium.gpg] https://pkg.helium.computer/deb stable main" | sudo tee /etc/apt/sources.list.d/helium.list
sudo apt update && sudo apt install helium-bin

# NVIDIA 595.58.03 production, closed flavor (Isaac Sim 6.1.0 tested)
# Method: NVIDIA CUDA network repo + cuda-keyring = Nvidia's official apt
# path for debian13, DKMS-integrated. Chosen over: Debian native apt (only
# has 550, no 595), the .run installer (Isaac docs suggest it, but it
# bypasses apt and breaks on kernel updates — Debian wiki discourages it),
# and local-repo .deb snapshots (frozen NFB builds + orphaned keyrings).
# Flavor: closed (nvidia-kernel-dkms). Do NOT install nvidia-open (open
# flavor), nvidia-smi (transitional dummy in 595 — real /usr/bin/nvidia-smi
# ships in nvidia-driver-cuda), or cuda-drivers (Replaces the open flavor).
# The pin locks the Isaac-tested version so apt can't drift to newer NFB
# branches (e.g. 615). Bump it only when Isaac re-tests a newer production.
# Needs SecureBoot disabled, or enroll the DKMS MOK when prompted.
sudo apt install -y linux-headers-amd64 dkms curl gnupg
cd /tmp && curl -fsSL -O https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i /tmp/cuda-keyring_1.1-1_all.deb
sudo tee /etc/apt/preferences.d/nvidia-595-pin > /dev/null <<'EOF'
Package: *nvidia* *cuda* libnv* libcuda1
Pin: version 595.58.03-1
Pin-Priority: 1000
EOF
sudo apt update
sudo apt install -y nvidia-driver nvidia-kernel-dkms firmware-nvidia-gsp libcuda1 nvidia-driver-cuda
sudo update-initramfs -u
echo "Reboot, then verify: nvidia-smi && cat /proc/driver/nvidia/version (want 595.58.03, no 'Open')"


