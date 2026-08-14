# AGENTS.md — Sway configuration knowledge base

Verified knowledge about how this sway setup works and how to configure
it. Facts marked **[source]** were checked in sway's source code;
**[tested]** were verified live against the running compositor. The
authoritative reference is `man 5 sway`.

## Layout & include order

- Main file: `config`. Include order:
  1. `/etc/sway/config.d/*` — Debian ships `50-systemd-user.conf`, which
     imports `DISPLAY`/`WAYLAND_DISPLAY`/`SWAYSOCK`/`XDG_CURRENT_DESKTOP`
     into the systemd user session.
  2. `variables` — shared defaults (`$mod`, `$term`, `$scripts`, ...).
  3. `config.d/*` — feature files (alphabetical: 0variables, autostart,
     input, keybindings, looks, navigation, output).
- There are NO per-machine files: the config is machine-agnostic. Output
  geometry is declared in `config.d/output` (see Dynamic outputs below),
  and the desk script derives its output mapping from monitor positions at
  runtime (see `scripts/desk`). Adding a new machine = adding output
  blocks (or relying on identifier blocks that follow the monitors).
- `include` supports globs; relative paths resolve against the config
  directory.

## Validation & reload

- `sway --validate -c ~/.config/sway/config` — parse-only validation.
  On this machine it always prints NVIDIA proprietary-driver errors
  (the session runs with `--unsupported-gpu`): expected noise, ignore.
- `swaymsg reload` — live reload; reload output reports config errors.
- `get_bindings` IPC type does NOT exist in sway 1.11 ("Unknown message
  type") — binding introspection is not possible; verify binds by
  reading the config and reloading.

## Variables

- `set $name value`; `$name` expands at parse time in any config line.
- Variables are NOT readable at runtime: no IPC exposes them, and
  scripts cannot query them. The desk scripts avoid config values
  entirely — they derive output names/order from `swaymsg get_outputs`
  at runtime.
- `$name` collision risk: short names are convenient but easy to
  collide with; document reserved names in comments.

## Keybindings

- `bindsym <combo> <command>` binds a keysym; `bindcode` binds a raw
  keycode (layout-independent). Flags exist: `--locked`, `--release`,
  `--to-code`, `--no-warn`, `--input-device=<dev>`, `--whole-window`.
- Keysym matching **[source]**: sway matches BOTH the raw (unshifted,
  level-0) keysym and the translated (modifier-applied) keysym of the
  pressed key. Consequence: `bindsym $mod+Shift+minus` fires when
  pressing Shift+minus even though the key produces `underscore`.
  (This differs from i3, where you must write `$mod+Shift+underscore`.)
- `--locked` makes a bind work while the screen is locked (used for
  media keys).
- `\@` escapes `@` in config lines (e.g. `pactl ... \@DEFAULT_SINK@`),
  otherwise sway treats `@...@` as its own syntax.
- Combo syntax: `$mod+Shift+grave` (backtick key is `grave`),
  `$mod+Left` / `Left`, `XF86AudioRaiseVolume`, `Print`, `Return`,
  `minus`, letters. Modifiers: `$mod` (a variable), `Shift`, `Ctrl`,
  `Alt`, `Mod1`-`Mod5`.
- Within a mode, a later binding overwrites an earlier one.
- Modes: `mode "name" { bindsym ... }` + `bindsym $mod+r mode "name"`
  creates key-submode contexts (e.g. the resize mode in keybindings);
  `mode "default"` returns to the base bindings.

## exec semantics (important!) **[source]**

- `exec` commands run ONLY at session start and are IGNORED on config
  reload (`cmd_exec` returns early when `config->reloading`).
  `exec_always` is the variant that also re-runs on reload.
- i3 re-runs `exec` on reload unless the process is still running; sway
  does not — so `exec` is safe for one-shot startup tasks without
  marker-file hacks.
- `exec` spawns via `sh -c`; tilde and environment expansion apply.
- Sway sets `SWAYSOCK`, `WAYLAND_DISPLAY`, `DISPLAY` for exec'd
  processes **[tested]** — scripts can rely on `$SWAYSOCK`.
- Caveat: config `exec` lines fire before output hotplug settles, so
  startup scripts that query outputs may need a short retry loop
  (see `scripts/desk start`).

## Command chaining & conditionals

- Chain commands with `,` (or `;`) in one line / one `swaymsg` call.
- A failing command does NOT abort the rest of the chain **[tested]**
  (e.g. `move container to workspace X` failing with "Can't move an
  empty workspace" still lets later `workspace` commands run).
- There are NO conditionals in sway config: no if/else, no criteria on
  `bindsym`. Branching must happen in scripts (query IPC, then send
  the right command).
- `swaymsg 'cmd1, cmd2'` sends a multi-command message in ONE IPC call
  — cheaper than spawning `swaymsg` twice.

## Workspaces & outputs

- `workspace <name> output <output>` statically assigns a workspace to
  an output; without an assignment, a new workspace is created on the
  currently focused output. As a RUNTIME command it only records the
  assignment for future creation — it does NOT move an existing workspace
  [source][tested]. To move a workspace, use `move workspace to output
  <name>` (moves the focused workspace; no-op if already there).
- `assign [criteria] workspace <name>` routes a window to a workspace
  regardless of how the app was launched (also works as a runtime
  command). Caveat: if the target workspace does not exist, it is created
  on the focused output — ensure placement first (pre-create it on the
  right output, or move it) when output correctness matters.

## Dynamic outputs

- Output geometry (mode/position) is declared directly in `config.d/output`
  (no shikane anymore).
- Matching is by name first, then by IDENTIFIER ("make model serial", see
  `swaymsg -t get_outputs`). ORDER MATTERS (sway quirk): a name-based block
  stored after an identifier block RESETS the identifier block's fields
  (supersede_output_config in sway/config/output.c). So name blocks come
  FIRST, identifier blocks LAST — the identifier then wins the merge.
- Name blocks (`eDP-1`, `HDMI-A-1`, `DP-1`) only apply when those outputs
  connect, so docked/undocked both work. Identifier blocks follow the
  physical monitor and are therefore machine-agnostic (e.g. the AOC/Samsung
  blocks for `mithrandir`). Mode is only set where a specific refresh is
  wanted; unset = preferred.
- Every `swaymsg reload` re-applies sway's stored output configs and any
  output without an explicit mode/position is forced to its preferred mode
  and auto-arranged (black flash + monitors jumping). Declaring the same
  values sway would otherwise keep makes reload a no-op.
- Because positions are pinned deterministically, the desk script
  (`scripts/desk`) derives its letter mapping (left→right = a, b, c...)
  from output positions at runtime — no per-machine config needed.
- There is NO hotplug re-apply daemon anymore (shikane + `restore_desk`
  are gone): after a dock/undock, sway re-applies the output blocks and
  the next `desk go`/`desk move` press re-pins every workspace.
- Each output shows its own workspace; `workspace 1a, workspace 1b`
  switches both outputs from a single bind (focus ends on the last).
- `focus output <name>` moves focus between outputs; chains well with
  `workspace` to create/switch a workspace on a specific output.
- `move container to workspace X` **[tested]**: focus STAYS on the
  source workspace; it does not follow the moved container. To land the
  user on the moved window, follow up with `workspace X`.
- Relative same-output moves exist natively: `move container to
  workspace next_on_output|prev_on_output` (wraps around). There is NO
  native "move to absolute desk N on the same output" — that needs a
  script (conditionals).
- Empty workspace lifetime is NOT guaranteed: sway destroys a workspace
  when its last container leaves while it is not visible, and may clean
  up other empty workspaces when they lose visibility — but empty
  workspaces can also persist. Never rely on an empty workspace
  existing; recreate it explicitly.
- `workspace --no-auto-back-and-forth <name>` opts a switch out of the
  (default off) back-and-forth toggle.
- Workspace names are arbitrary strings; `<digit><letter>` naming works
  fine (e.g. `1a`, `0b`).
- Scratchpad: `move scratchpad` / `scratchpad show`; scratchpad windows
  live under the `__i3_scratch` workspace in the tree.

## swaymsg / IPC

- Message types: `get_tree` (full tree, large payload), `get_workspaces`
  (small; fields `name`, `focused`, `visible`, `output`), `get_outputs`
  (names, geometry, `current_workspace`), `get_version`, `get_inputs`,
  `get_seats`, `subscribe` (event stream), `reload`, `exit`.
- `-r/--raw` returns compact JSON (prefer for parsing); `-q/--quiet`
  suppresses the reply; `-p/--pretty` forces pretty output.
- Exit code 0 = success, 2 = the command failed (e.g. "Can't move an
  empty workspace"). Useful for scripting.
- No `--dry-run` flag in swaymsg 1.11.
- Prefer `get_workspaces` over `get_tree` when only focus/output info
  is needed — much smaller payload, faster parse.
- In `get_tree`, container nodes have `"output": null`; only workspace
  nodes carry the output name. To find a container's output, walk up to
  its workspace ancestor, e.g. with jq:
  `.. | objects | select(.type == "workspace") | . as $ws | .. | objects | select(.id == $id) | $ws.name`
- The focused container in `get_tree` has `"focused": true`; the
  focused workspace is also flagged in `get_workspaces`.

## Shell scripting (repo scripts use POSIX sh)

- `#!/bin/sh` on Debian is dash: NO process substitution (`< <(...)`),
  NO arrays, NO nested parameter expansion (`${x%"${x#?}"}` fails with
  "Bad substitution").
- dash DOES support `${var:offset:length}` substring expansion.
- Word-splitting gotcha: a list built as `x="$x$y"` ("ab") does NOT
  split in `for i in $x`; build space-separated strings and trim.
- `jq` is the JSON parser used by the scripts — it is a required
  dependency on any machine using this config.
- The "query then act" pattern is one `get_*` query + one chained
  `swaymsg` command. The desk script (`scripts/desk`) reads everything it
  needs (sorted outputs AND the focused output) from a single
  `get_outputs` call — 1 IPC + 1 chained command per keypress.

## Input, looks & bar

- Keyboard: `input type:keyboard { xkb_layout ... xkb_variant ...
  repeat_rate 50 repeat_delay 250 }` — defaults are 25 cps / 600 ms.
- `seat * hide_cursor 3000` — auto-hide the pointer after N seconds.
- Aesthetics: `default_border pixel 2`, `default_floating_border
  pixel 2`, `gaps inner 4`, `hide_edge_borders smart`.
- `floating_modifier $mod normal` — drag with $mod+LMB, resize with
  $mod+RMB (works for tiled windows too).
- Bar + DE pieces: quickshell (stow package `quickshell/`, one process,
  gruvbox theme), started from `config.d/autostart` via
  `exec_always sh -c 'pkill -x quickshell 2>/dev/null; sleep 0.2; exec
  quickshell'` — the pkill prevents duplicate shells on reload. It provides
  the right bar (workspaces/taskbar/tray/volume/...), launcher (`$mod+d`),
  notifications (daemon + popup + center), OSD, polkit agent, lock screen
  (`$mod+P` / swayidle), clipboard, network menu, screenshot picker (grim)
  — all driven through `quickshell ipc call …` (see PLAN-quickshell.md in
  the repo root). No swaybar/waybar/rofi/swaylock configs live in this repo
  anymore (removed 2026-08-14, phase 8).
- `focus_follows_mouse no` + `focus_wrapping` control pointer/keyboard
  focus behavior across outputs.

## Environment notes (this machine)

- sway 1.12 on Arch; NVIDIA proprietary GPU, started with
  `--unsupported-gpu` (hence validate noise).
- Audio: pipewire + pipewire-pulse + wireplumber running; `wpctl` is
  available. `pactl`, `brightnessctl`, `grim`, `slurp`, `wl-copy` are
  NOT installed — binds calling them fail silently.
- The config directory is self-contained (scripts live in `scripts/`,
  referenced via `$scripts` from `variables`) so it can be synced to
  other machines; only dependency outside the folder is `jq`.
- Desk-switching (workspace management) is implemented by `scripts/desk`
  (`desk go` / `desk move` / `desk start`, bound in `config.d/navigation`);
  see the script header. Output geometry lives in `config.d/output` (see
  the Dynamic outputs section above); desk letters are positional
  (left→right = a, b, c...).
