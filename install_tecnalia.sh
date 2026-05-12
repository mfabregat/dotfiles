# Remove unattended-upgrades
sudo apt remove unattended-upgrades

# Install git
sudo apt install git git-lfs
git config --global user.name "Marc Fabregat"
git config --global user.email "marc.fabregat@tecnalia.com"

# Follow instructions under https://github.com/IsmaelMartinez/teams-for-linux
sudo wget -qO /etc/apt/keyrings/teams-for-linux.asc  https://repo.teamsforlinux.de/teams-for-linux.asc
echo "deb [signed-by=/etc/apt/keyrings/teams-for-linux.asc arch=$(dpkg --print-architecture)] https://repo.teamsforlinux.de/debian/ stable main" | sudo tee /etc/apt/sources.list.d/teams-for-linux-packages.list

ssh-keygen -t ed25519 -C "marc.fabregat@tecnalia.com"

# Add ed25519.pub to https://git.code.tecnalia.dev/-/user_settings/ssh_keys

# Artifactory needs https authentication. Generate identity token.

# Artifactory setup:
git config credential.helper store
git clone git@git.code.tecnalia.dev:tecnalia_robotics/rob4green/cranebot_workcell.git
# And paste the identity token