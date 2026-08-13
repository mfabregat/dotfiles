#!/bin/sh
# player_focus.sh - focus the active MPRIS player's window (waybar mpris
# module on-click-middle handler).
#
# 1. If the player has a window, focus it by pid (works regardless of app_id).
# 2. If it is running headless, ask it to show its main window by activating
#    the "Show ..." entry of its StatusNotifier tray menu - the same thing as
#    right-clicking its tray icon -> Show. Needed because some players (this
#    Spotify build) silently absorb a plain relaunch while an instance is
#    already running.
# 3. As a last resort, launch the app through its desktop entry.
#
# Dependencies: playerctl, pgrep, swaymsg, busctl, dbus-send, gtk-launch.

player=$(playerctl metadata --format '{{playerName}}' 2>/dev/null) || exit 0
[ -n "$player" ] || exit 0

# 1. Focus an existing window by pid.
pid=$(pgrep -x "$player" | head -1)
if [ -n "$pid" ] && swaymsg "[pid=$pid] focus" >/dev/null 2>&1; then
  exit 0
fi

# 2. Headless: activate the player's tray-menu "Show ..." item.
#    RegisteredStatusNotifierItems entries look like
#    ":1.1688/org/ayatana/NotificationItem/spotify_client" (bus name / path).
items=$(busctl --user get-property org.kde.StatusNotifierWatcher \
  /StatusNotifierWatcher org.kde.StatusNotifierWatcher \
  RegisteredStatusNotifierItems 2>/dev/null) || exit 0
item=$(printf '%s\n' "$items" | sed -n \
  's/.*"\(:[0-9][0-9.]*\)\/\([^"]*\)".*/\1 \2/p' | \
  awk -v p="$player" 'index(tolower($2), tolower(p)) {print; exit}')

if [ -n "$item" ]; then
  set -- $item
  name=$1
  menu="/$2/Menu"

  # Find the id of the "Show ..." item in the D-Bus menu layout.
  layout=$(dbus-send --session --dest="$name" --type=method_call --print-reply \
    "$menu" com.canonical.dbusmenu.GetLayout int32:0 int32:-1 array:string: \
    2>/dev/null) || exit 0
  item_id=$(printf '%s\n' "$layout" | awk '
    /int32 [0-9]+/ { id = $2 }
    /Show / { print id; exit }
  ')

  if [ -n "$item_id" ]; then
    dbus-send --session --dest="$name" --type=method_call "$menu" \
      com.canonical.dbusmenu.AboutToShow int32:0 >/dev/null 2>&1
    dbus-send --session --dest="$name" --type=method_call "$menu" \
      com.canonical.dbusmenu.Event int32:"$item_id" string:clicked \
      variant:uint32:0 uint32:0 >/dev/null 2>&1
    exit 0
  fi
fi

# 3. Launch the app (player not running, or no tray menu available).
gtk-launch "$player" >/dev/null 2>&1 || true
