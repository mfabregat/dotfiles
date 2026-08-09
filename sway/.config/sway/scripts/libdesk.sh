#!/bin/sh
# libdesk.sh — shared helpers for the desk scheme (sourced by goto_desk,
# move_to_desk, startup_desk). IMPORTANT: keep this file free of literal
# `set $x` lines so the overlay lookup below stays unambiguous.
#
# The machine overlay (mithrandir/tecnalia — the config file defining the
# output variables) is the single source of truth:
#   set $desks 9            optional, default 9
#   set $a DP-1             -> workspace letter a
#   set $b HDMI-A-1         -> workspace letter b
#   ... up to $i (9 outputs), defined contiguously
# Only outputs currently connected are used (dock/undock safe).
#
# Cost per script: 1 get_workspaces query + 1 chained swaymsg command.

SWAY_DIR="${SWAY_DIR:-$HOME/.config/sway}"
OUTPUT_LETTERS="a b c d e f g h i"

die() { printf 'desk: %s\n' "$*" >&2; exit 1; }

# load_desk_map — sets: desks, letters (active letters), nouts, out_<letter>
load_desk_map() {
	overlay=$(grep -l '^set \$[a-i] ' "$SWAY_DIR"/* 2>/dev/null | head -1)
	[ -n "$overlay" ] || die "no machine overlay defining output letters in $SWAY_DIR"
	desks=$(sed -n 's/^set \$desks \([0-9][0-9]*\)$/\1/p' "$overlay" | head -1)
	desks=${desks:-9}
	case "$desks" in
		[1-9]|[1-8][0-9]) ;;
		*) die "invalid \$desks in $overlay" ;;
	esac
	connected=$(swaymsg -t get_outputs -r | jq -r '.[].name' | tr '\n' ' ')
	letters=""
	nouts=0
	for letter in $OUTPUT_LETTERS; do
		out=$(sed -n "s/^set \$$letter \([^ ]*\)\$/\1/p" "$overlay" | head -1)
		[ -n "$out" ] || break
		case " $connected " in
			*" $out "*)
				eval "out_$letter=\"$out\""
				letters="$letters $letter" # space-separated, for word splitting
				nouts=$((nouts + 1))
				;;
		esac
	done
	letters=${letters# } # strip leading space
	[ "$nouts" -ge 1 ] || die "no mapped outputs are connected"
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
