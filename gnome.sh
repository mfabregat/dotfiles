#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Dynamically find the directory where this script lives
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="$DOTFILES_DIR/gnome/.config/dconf/gnome-settings.ini"

show_help() {
    echo "GNOME Configuration Sync Utility"
    echo "Usage: $0 [save|load]"
    echo "  save    Dump current desktop settings to plain text"
    echo "  load    Apply saved settings to the active desktop"
}

save_settings() {
    echo "💾 Dumping GNOME settings to text..."
    # Ensure the target directory exists
    mkdir -p "$(dirname "$CONFIG_PATH")"
    dconf dump /org/gnome/ > "$CONFIG_PATH"
    echo "✅ Saved to: $CONFIG_PATH"
    echo "🚀 Ready to git commit!"
}

load_settings() {
    if [ ! -f "$CONFIG_PATH" ]; then
        echo "❌ Error: Configuration file not found at $CONFIG_PATH"
        exit 1
    fi
    echo "🔄 Loading GNOME settings into dconf database..."
    dconf load /org/gnome/ < "$CONFIG_PATH"
    echo "✅ Settings applied successfully!"
}

# Parse command line arguments
case "$1" in
    save)
        save_settings
        ;;
    load)
        load_settings
        ;;
    *)
        show_help
        exit 1
        ;;
esac