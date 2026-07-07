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
stow <package_name>
```

## Adding a new config

To add a new configuration file, simply create the file in the corresponding package directory and then run `stow` to create the symlink. For example, for `kitty`:

```bash
mkdir -p ~/dotfiles/kitty/.config
mv ~/.config/kitty ~/dotfiles/kitty/.config/
cd ~/dotfiles
stow kitty
```
