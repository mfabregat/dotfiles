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
git clone https://github.com/mfabregat/dotfiles
cd dotfiles
stow package
```

## Update a config

To update a configuration file, simply edit the file in the corresponding package directory (in this directory) and then run `stow` again to update the symlinks. For example, if you want to update your `vim` configuration, you can edit the `vimrc` file in the `vim` directory and then run:

```bash
stow vim
```

If the update has been done directly in the config directory, you must update the dotfiles:

```bash
```

## Adopt a new package

To adopt a new package, you can create a new directory for it in the repository and add your configuration files there. For example, if you want to add configuration for `vim`, you can create a `vim` directory and place your configuration file inside it. Then, you can use `stow` to create symlinks for the new package:

```bash
mkdir vim
# Add your configuration files to the vim directory
mv ~/.vimrc vim/
stow vim
```
