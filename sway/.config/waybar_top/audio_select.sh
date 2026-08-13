#!/bin/sh
# audio_select.sh <slot> - switch the default audio output device.
#
# Invoked by waybar's menu-actions with the clicked menu item id (sink1..
# sink8); the slot is resolved to a PipeWire node id via the map written by
# audio_menu.sh.

set -eu

slot="${1:-}"
[ -n "$slot" ] || { echo "usage: audio_select.sh <slot>" >&2; exit 1; }

map="${XDG_CACHE_HOME:-$HOME/.cache}/waybar/audio_sinks.map"
id="$(awk -v s="$slot" '$1 == s { print $2; exit }' "$map" 2>/dev/null || true)"
[ -n "$id" ] || { echo "audio_select.sh: no device for '$slot' (run audio_menu.sh)" >&2; exit 1; }

wpctl set-default "$id"
