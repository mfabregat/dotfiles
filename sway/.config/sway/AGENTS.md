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
  3. `config.d/*` — feature files (alphabetical: bar, input,
     keybindings, looks, navigation, output).
- There are NO per-machine files: the config is machine-agnostic. Output
  geometry lives in shikane (see Dynamic outputs below), and the desk
  scripts derive their output mapping from monitor positions at runtime
  (see scripts/libdesk.sh). Adding a new machine = adding a shikane
  profile, nothing in sway config.
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
  (see `scripts/startup_desk`).

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

## Dynamic outputs (shikane)

- Output geometry (mode/position/scale/transform) is NOT configured in
  sway anymore. `shikane` (~/.config/shikane/config.toml, stow package
  `shikane/`) applies a matching profile at startup and on hotplug via the
  wlr-output-management protocol. Started from `config.d/autostart` with
  `exec_always sh -c 'pgrep -x shikane || exec shikane'` — guarded so a
  sway reload does NOT restart it (a restart re-applies the profile =
  modeset = brief black flash). Config changes are picked up with
  `shikanectl reload`; shikane does not watch its config file.
- Profile matching is exact: a profile applies only when every output in
  it matches a connected display AND every connected display is matched.
  Profiles for different machines coexist; only the matching one wins
  (e.g. `mithrandir` on the desktop, `tecnalia-laptop` vs
  `tecnalia-docked` on the laptop). Displays are matched by name
  (`n=DP-1`); regenerate with `shikanectl export <name>` for
  vendor/model/serial matching.
- Because shikane pins positions deterministically, the desk scripts can
  derive their letter mapping (left→right = a, b, c...) from output
  positions at runtime — no per-machine config needed.
- Per-profile `exec` commands run with `$SHIKANE_PROFILE_NAME` set
  (per-output with `$SHIKANE_OUTPUT_NAME`). We use it to run
  `scripts/restore_desk` after a profile is applied, so a dock/undock
  re-applies the current desk to all connected outputs instead of waiting
  for the next $mod+N press. `restore_desk` reads the focused workspace
  name, extracts its desk number and delegates to `goto_desk`.
- Reload the config without restarting: `shikanectl reload`.
- Keep sway's `output * bg` (wallpaper) in `config.d/output` — shikane
  does not touch background/scale of swaybg.
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
- The "query then act" pattern costs 2 IPC calls: one small `get_*`
  query + one chained `swaymsg` command. Both can be `--quiet`/`-r`.

## Input, looks & bar

- Keyboard: `input type:keyboard { xkb_layout ... xkb_variant ...
  repeat_rate 50 repeat_delay 250 }` — defaults are 25 cps / 600 ms.
- `seat * hide_cursor 3000` — auto-hide the pointer after N seconds.
- Aesthetics: `default_border pixel 2`, `default_floating_border
  pixel 2`, `gaps inner 4`, `hide_edge_borders smart`.
- `floating_modifier $mod normal` — drag with $mod+LMB, resize with
  $mod+RMB (works for tiled windows too).
- Bar: waybar (not swaybar), started via `exec_always sh -c 'pkill -x
  waybar; ~/.config/waybar/audio_menu.sh; exec waybar'`. sway re-runs
  exec_always on reload WITHOUT stopping the old instance, so the pkill is
  what prevents duplicate bars. audio_menu.sh regenerates the audio widget's
  right-click device menu (menu XML is only read by waybar at startup);
  reload sway to pick up newly connected devices. Runtime files live in
  `~/.cache/waybar/` (NOT in the repo, which is stow-symlinked):
  `audio_menu.xml` (GtkMenu) and `audio_sinks.map` (slot -> PipeWire node
  id). `menu-actions` slots in config.jsonc are static (`sink1..sink8`);
  `~/.config/waybar/audio_select.sh <slot>` resolves the slot via the map and
  runs `wpctl set-default` (the bar's volume display updates live via the
  wireplumber module; no waybar reload is needed).
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
- Desk-switching (workspace management) is implemented by the scripts
  in `scripts/` (`goto_desk`, `move_to_desk`, `startup_desk` +
  `libdesk.sh` + `restore_desk`); see the script headers and
  `config.d/navigation`. Output geometry is shikane's job (see the
  Dynamic outputs section above); desk letters are positional
  (left→right = a, b, c...).
