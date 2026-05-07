ssh-keygen -t ed25519 -C "marc.fabregat@tecnalia.com"

# Add ed25519.pub to https://git.code.tecnalia.dev/-/user_settings/ssh_keys

# Artifactory needs https authentication. Generate identity token.

# Artifactory setup:
git config credential.helper store
git clone git@git.code.tecnalia.dev:tecnalia_robotics/rob4green/cranebot_workcell.git
# And paste the identity token
