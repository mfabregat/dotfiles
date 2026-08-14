# Dotfiles

This repository contains my personal dotfiles and configuration files for various tools and applications.

## Installation

The only dependencies are `git` and `stow`. You can install them using your package manager. For example, on Ubuntu, you can run:

```bash
sudo apt update
sudo apt install git stow
```

## Usage

To install the dotfiles, clone this repository and use `stow` to create symlinks in your home directory:

```bash
cd ~
git clone https://github.com/mfabregat/dotfiles
cd ~/dotfiles
stow package
```

## Colors

All colors are defined once in [`palette/palette.json`](palette/palette.json)
(quickshell, sway, helium, ghostty derive from it). To restyle everything:

```bash
python3 palette/generate.py   # regenerate derived configs (no restow needed)
```

See [`palette/README.md`](palette/README.md).

## Adding a new config

To add a new configuration file, simply create the file in the corresponding package directory and then run `stow` to create the symlink. For example, for `package`:

```bash
mkdir -p ~/dotfiles/package/.config
mv ~/.config/package ~/dotfiles/package/.config/
# You may need to move more files depending on the package configuration structure
cd ~/dotfiles
stow package
```

## GNOME and Ubuntu settings

Because GNOME settings are stored in a binary database (`dconf`) under `~/.config/dconf/user`, they cannot be symlinked directly via Stow. A helper script manages syncing these settings as a plain text `.ini` file.

To save your current GNOME settings to the repository, run:

```bash
./gnome.sh save
```

To restore the settings from the repository, run:

```bash
./gnome.sh load
```
