#!/bin/sh
# libdesk.sh — shared helpers for the desk scheme (sourced by goto_desk,
# move_to_desk, startup_desk, restore_desk).
#
# Desk letters are POSITIONAL: connected outputs are sorted by their
# position in the global coordinate space (left→right, top→bottom) and
# mapped to a, b, c, ... Shikane (~/.config/shikane/config.toml) pins
# output geometry per machine/profile, so the letter order is
# deterministic for a given arrangement (dock/undock stable).
#
# There is no per-machine config anymore: sway config is machine-agnostic
# and the letter mapping is derived at runtime. $desks is fixed at 9
# (bindings go up to $mod+9).
#
# Cost per script: 1 get_outputs query + 1 chained swaymsg command.

OUTPUT_LETTERS="a b c d e f g h i"
desks=9

die() { printf 'desk: %s\n' "$*" >&2; exit 1; }

# load_desk_map — sets: letters (active letters), nouts, out_<letter>
load_desk_map() {
	letters=""
	nouts=0
	for out in $(swaymsg -t get_outputs -r | jq -r '[.[] | select(.active) | {name, x: .rect.x, y: .rect.y}] | sort_by(.x, .y) | .[].name'); do
		letter=$(printf '%s' "$OUTPUT_LETTERS" | cut -d' ' -f$((nouts + 1)))
		[ -n "$letter" ] || break # more outputs than letters
		eval "out_$letter=\"$out\""
		letters="$letters $letter" # space-separated, for word splitting
		nouts=$((nouts + 1))
	done
	letters=${letters# } # strip leading space
	[ "$nouts" -ge 1 ] || die "no outputs connected"
}

# desk_switch_chain <desk> <last-letter> — print a sway command chain that
# brings up <desk> on every connected output, ending focus on <last>.
# Each workspace is pinned for future creation (workspace X output Y) AND
# actively moved to its output (move workspace to output Y), so misplaced
# workspaces self-heal whenever a desk is opened.
desk_switch_chain() {
	desk=$1
	last=$2
	chain=""
	for letter in $letters; do
		[ "$letter" = "$last" ] && continue
		eval "out=\$out_$letter"
		chain="$chain workspace ${desk}${letter} output $out, focus output $out, workspace --no-auto-back-and-forth ${desk}${letter}, move workspace to output $out,"
	done
	eval "out=\$out_$last"
	chain="$chain workspace ${desk}${last} output $out, focus output $out, workspace --no-auto-back-and-forth ${desk}${last}, move workspace to output $out"
	printf '%s' "$chain"
}

# focused_letter — set ws (focused workspace name) and letter (its output's
# letter), dies if the focused output is not in the desk scheme.
focused_letter() {
	line=$(swaymsg -t get_workspaces -r | jq -r '.[] | select(.focused) | "\(.name) \(.output)"')
	ws=${line% *}
	out=${line#* }
	letter=""
	for l in $letters; do
		eval "o=\$out_$l"
		[ "$o" = "$out" ] && letter=$l
	done
	[ -n "$letter" ] || die "focused output \"$out\" is not in the desk scheme"
}
