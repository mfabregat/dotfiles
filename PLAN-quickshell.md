# Plan: Port sway desktop environment to Quickshell

Status: **approved blueprint** — implementation follows the phases below.
Date: 2026-08 · Quickshell 0.3.0 (Arch `extra/quickshell`, latest release, docs at `quickshell.org/docs/v0.3.0`)

## ⚠️ Agent working rules (learned the hard way — read first)

1. **Verify before tagging a landmine.** Most "landmines" recorded in this
   plan turned out to be **false or misdiagnosed** when actually verified
   (see the Landmine audit below): PopupWindow is not broken, QML function
   calls *are* reactive, inline components *can* see root props, `index`
   works in delegates (unless `required property var modelData` is
   declared), and structural hot reloads do map. A tagged landmine without
   a minimal reproduction is a bug report written by someone who didn't
   file it. **Before recording or working around any suspected limitation:
   reproduce it in a throwaway config** (`quickshell -p /tmp/…`, separate
   instance, live logs) and only then decide.
2. **Never trust a claim that contradicts the docs without a repro** — the
   quickshell docs were right where the code comments were wrong.
3. **No visual verification by the agent.** The model must only verify via
   command-line / programmatic means: quickshell logs, `quickshell ipc`,
   `swaymsg -t get_tree/get_seats`, unit tests (e.g. `node`), grep over
   qmltypes/source. When a visual check is genuinely needed (appearance,
   animation, layout), **ask the user to verify** — never screenshot.

## Efficiency, optimization & portability playbook (verified 2026-08-13)

Read before touching any shell code. Everything below was verified against the
installed 0.3.0-2 package (qmltypes under `/usr/lib/qt6/qml/Quickshell/**/*.qmltypes`,
the shipped `Io/FileView.qml` wrapper, and live logs).

### Verified API facts (avoid re-discovering these)

- **ObjectModel vs list properties are NOT interchangeable.** Exports typed as
  `UntypedObjectModel` (alias `Quickshell/ObjectModel`) expose `.values` +
  `valuesChanged` only — no `.length`: `I3.monitors`, `I3.workspaces`,
  `SystemTray.items`, `Mpris.players`, `DesktopEntries.applications`,
  `ToplevelManager.toplevels`, `Networking.devices`, `Pipewire.nodes`,
  UPower devices. But `Quickshell.screens` is a **list property** — `.length`
  and `screens[i]` work there and `.values` does NOT exist. Landmine 1's
  blanket wording is wrong for screens; `Quickshell.screens.length` in
  Osd.qml/Notifications.qml is correct as written.
- **Binding dependency tracking:** reads of tracked (notify-carrying) QObject
  properties — including inside QML JS functions — re-evaluate bindings.
  Reads *inside native C++ method calls* do not. So `I3.monitorFor(screen)`
  still needs the `I3.monitors.values.length ? … : null` guard (native
  method), while `I3.focusedMonitor` (notify property) and the screens list
  need no guard. The comment framing "a bare function call evaluates once"
  is wrong — say "native method internals aren't tracked" instead.
- **FileView is a trigger + blocking reader, not a reactive property.** The
  shipped wrapper exposes properties `path`/`preload`/`blockLoading`/
  `blockAllReads`/`printErrors` and **functions** `text()`/`data()` that
  force a read (microseconds on sysfs). React to signals `loaded` /
  `fileChanged` and read imperatively; never bind to a file's contents.
  **Correction (verified 2026-08-13, throwaway config):** `text()` returns
  the internal buffer, which the watcher does NOT refresh on `fileChanged`
  (stale read — preload:true returned the old value; preload:false returned
  empty). The reliable pattern: `preload: true` for the initial read,
  `onFileChanged: fv.reload()`, then read `text()` from
  `onInternalTextChanged`/`onLoaded` (both fire after the async re-read;
  updates are idempotent).
- **Process** (`Quickshell.Io`): `command` is a string list (no shell),
  `stdout: StdioCollector { onStreamFinished }`, `running: true` re-execs on
  every trigger; use `runningChanged` to chain steps (no Timers needed).
- **SystemClock** exposes `hours`/`minutes`/`seconds` + `date` — no need for
  `Qt.formatDateTime` for the clock widgets.
- **Phase 6-8 natives present:** `WlSessionLock`/`WlSessionLockSurface`
  (`Quickshell.Wayland`), `IdleInhibitor` (`Quickshell.Wayland._IdleInhibitor` —
  native idle inhibition, no D-Bus ScreenSaver glue daemon needed for the
  screenshot picker), `ScreencopyView` exists but the plan deliberately
  avoids it, `ToplevelManager.Toplevel` (`appId`/`title`/`activated` +
  `activate()`/`close()`) for window actions without swaymsg.

### Process-spawn budget (measured)

- One spawn ≈ 1 ms + child setup; the idle shell should stay **≲ 1 spawn/s**.
  Prefer event-driven (Pipewire signals, FileView inotify, native models,
  notification driver one-shot timer) over any periodic ticker.
- `CpuMemTemp` polls at 1 Hz and spawns sh + grep + awk + N×cat + sort + tail
  (≈ 10 forks/s with 6 hwmon sensors). One `sh -c 'cat /proc/stat
  /proc/meminfo /sys/class/hwmon/hwmon*/temp*_input 2>/dev/null'` ≈ 2 forks/s,
  same parse (meminfo lines then carry `MemTotal:` prefixes — parse the first
  number per line). 1 Hz is the old waybar cadence, keep it.
- **Brightness reads should be fully native** (FileView): watch the device's
  `brightness` file, compute percent = raw / max_brightness (both readable
  via `text()`). The current 2 s `brightnessctl -m get` safety poll is a
  redundant 0.5 spawn/s forever on kernels where sysfs inotify works — and
  that it works was *verified* here (kernel 7.1.8 + throwaway config). The
  "inert sysfs inotify" worry was never reproduced — don't keep permanent
  pollers for unverified failure modes. Keep `brightnessctl` only for
  **writes** (udev perms); reads via sysfs make the shell work on machines
  where brightnessctl isn't installed (portability win — availability probes
  must check the API/sysfs directly, never an optional binary).
- `BacklightWidget` wheel: each tick spawns brightnessctl; coalesce rapid
  wheel deltas if it ever feels laggy (volume widget is native and needs no
  such care).

### Windows & rendering

- `visible: false` unmaps layer surfaces — hidden fullscreen transparent
  windows (launcher/center/polkit/OSD) cost nothing to composite. Eager
  creation + visibility toggle is the pattern; landmine 7's "lazy creation
  race" was not re-verified in the audit, but eager is the simpler, safer
  choice anyway — keep it.
- Do NOT merge the three fullscreen grab overlays (launcher/center/polkit)
  into one window: a polkit prompt can arrive while the launcher is open and
  the surfaces must grab independently.
- Repaint only on change: Canvas `onValuesChanged: requestPaint()`
  (sparklines), `Behavior on color` for hovers. No always-on animations.
- `Variants { model: Quickshell.screens }` per-screen windows is the verified
  pattern — keep it for phase 6's lock surfaces.

### Measured scale (anti-optimization guard)

- 39 desktop entries on this machine: the launcher's per-keystroke
  `buildResults` re-scores all entries in sub-ms — **do not add debouncing
  or haystack caches** for the current scale (only revisit at 500+ entries).
- 16 cores / 6 hwmon sensors / 3 screens: the fork reduction above matters
  more than any in-QML micro-optimization.

### Simplification opportunities found in review (fix when you touch the file)

- `NetworkWidget.findActive`: the `i === 0 ? networks : d.networks.values`
  index hack can miss a wired connection when a wifi device exists. Check
  the wifi device's networks first, then *every* device's own networks.
- `MprisWidget.focusPlayerWindow`: replace the pgrep+swaymsg shell spawn with
  a `ToplevelManager.toplevels` appId match + `activate()` (native, no
  subprocess, matches the plan's "focus via I3" intent).
- `TrayWidget` sets both `height` and `Layout.preferredHeight` — the
  parent is a plain `Column` (not a Layout), so `Layout.preferredHeight`
  is inert there: drop it and keep `height` (the sizing property).
- Duplicated helpers (`focusedScreen()` in Osd/Notifications, the
  `i3Monitor` guard in Launcher/Center/Polkit/Workspaces) are a deliberate
  plan decision; extract a shared `services/util` module only if a 4th copy
  of the same helper appears.
- Dead until phase 6: PowerMenu's Lock row calls `quickshell ipc call lock
  lock` — the target doesn't exist yet (harmless, just don't test it as
  "broken").

### Portability rules

- Availability probes check the API/sysfs directly, never an optional binary
  (see brightness above). Writes may require a binary (brightnessctl),
  reads should not.
- Keep hardware scans machine-agnostic: hwmon `temp*_input` max = hottest
  sensor on any machine — no per-machine hwmon path (old waybar had one;
  don't reintroduce it).
- sway integration goes through `quickshell ipc call …` + the I3 module;
  never parse `swaymsg -t get_tree` (sway `get_workspaces` has no node
  trees — verified).
- `DesktopEntries` scan is async — every icon/app lookup must track
  `DesktopEntries.applications.values` (the launcher and taskbar already do).
- **Never run unattended PAM-triggering tests** (faillock deny=3 → 10-min
  lock of sudo/su/login). Phase-6 lock and any polkit/pkexec test must be
  interactive or scripted against a mock.
- New machines need (install.md, phase 8): quickshell 0.3.0 (pin), pipewire
  (wpctl), brightnessctl (writes), polkit, NetworkManager, UPower,
  wl-clipboard (phase 7), ttf-noto-nerd + ttf-jetbrains-mono-nerd, grim.
- Keep the wallpaper-blur lock (no screencopy, no warm-up races); verify
  `--locked` media keys still work on sway 1.12.

## Goals

- Replace waybar (both bars), rofi, swaylock, swaynag, and the waybar helper
  scripts with **one quickshell config** (single process, single theme).
- Keep the current *feel* and the **gruvbox** palette.
- Add missing DE pieces: notification daemon, polkit agent, OSD, idle lock.
- Add chosen extras: control center, clipboard manager, network menu,
  night-light toggle, screenshot area picker.

## Research summary (verified sources)

- **Official docs** (quickshell.org/docs/v0.3.0): module list, I3 module,
  WlSessionLock, NotificationServer, Pipewire/Mpris/SystemTray/UPower/Pam/
  Polkit services, `qs.` module imports, hot reload, Variants multi-monitor.
- **zackbartel.com/blog/2026/07/quickshell**: full waybar+rofi+swaync+hyprlock
  → quickshell migration report. Lessons: lock screen (PAM) is the hardest
  part; idle inhibition via D-Bus ScreenSaver needs a glue daemon (Hyprland-
  specific; **sway handles fullscreen idle-inhibit natively — not needed**).
- **caelestia-dots/shell** (github): complete shell — lock with WlSessionLock +
  PamContext + bundled `assets/pam.d` + screencopy warm-up trick for blur +
  IpcHandler (`target: "lock"`) so swayidle can call `quickshell ipc call lock lock`.
  We deviate on the blur: the lock uses a blurred `wallpaper.jpg`, not screencopy.
- **ekremx25/quickshell**: full shell; its "blue-light filter" is a QML wrapper
  around **gammastep** (`-O <K>` / `-x`) — quickshell cannot do gamma itself.
- **programmersd21/the_quickshell_book**: folder-structure conventions
  (`bar/ popups/ widgets/ services/ util/ assets/`, PascalCase files, `qs.`
  imports). Code samples cross-checked against official docs (some are wrong,
  e.g. a non-existent `Quickshell.Services.Sway` — the real module is `Quickshell.I3`).

## Scope

### Replaced (removed from session)
| Current | Replacement |
|---|---|
| waybar (right bar) | `bar/` vertical PanelWindow |
| waybar_top (top bar) | merged into the right bar (user decision: single right bar) |
| rofi | `popups/Launcher.qml` (drun only) |
| swaylock | `lock/` — WlSessionLock + PAM, blurred wallpaper bg |
| swaynag (exit confirm) | `popups/ConfirmDialog.qml` |
| waybar custom/power + power_menu.xml | `popups/PowerMenu.qml` |
| audio_menu.sh / audio_select.sh | Pipewire service sink list popup |
| player_focus.sh | Mpris click → focus player window via I3.dispatch |
| gammastep-indicator (tray app) | `services/NightLight.qml` (wraps gammastep) |

### Added (missing DE pieces)
- Notification daemon (NotificationServer) + popup + center
- OSD (volume via Pipewire watch, brightness via sysfs poll)
- Polkit agent (Quickshell.Services.Polkit)
- swayidle: idle → lock → DPMS off (not present today)
- Control center, clipboard manager, network menu, screenshot area picker

### Kept (sway-side)
sway config (keybindings/outputs/input), desk scripts (goto_desk,
move_to_desk, startup_desk, libdesk.sh, bg_app), autotiling, spotify-bg,
swaybg (wallpaper via `output * bg`), gammastep (backend only), grimshot
(until the area picker replaces it), gnome-keyring, ghostty, fonts.

## Architecture

```
dotfiles/quickshell/.config/quickshell/     (stow package "quickshell")
  shell.qml              # entry: ShellRoot, staged loading (bar → services → popups)
  Theme.qml              # pragma Singleton — gruvbox palette + spacing/radius/fonts
  bar/
    RightBar.qml         # vertical PanelWindow (per-screen via Variants)
    Workspaces.qml       # desk pills (I3.workspaces, per-monitor)
    Taskbar.qml          # toplevels (click focus / middle close)
    ClockWidget.qml      # SystemClock
    Tray.qml             # SystemTray + DBusMenu
    ...                  # cpu, memory, temp, battery, network, volume, mpris, language
  popups/
    Launcher.qml         # drun (DesktopEntry model + fuzzy search)
    CalendarPopup.qml
    PowerMenu.qml        # lock/logout/suspend/reboot/shutdown + confirm dialog
    AudioMenu.qml        # Pipewire sink list
    NotificationCenter.qml
    ControlCenter.qml    # volume/brightness sliders, night light, wifi, power
    NetworkMenu.qml
    ClipboardPopup.qml
    ScreenshotPicker.qml # fullscreen overlay + grim -g
  lock/
    Lock.qml             # WlSessionLock + IpcHandler target "lock"
    LockSurface.qml      # per-screen surface: blurred wallpaper.jpg (via Wallpaper service), keyboard grab
    Pam.qml              # PamContext (passwd) + custom pam.d dir
    assets/pam.d/        # bundled PAM service config
  services/              # singletons: CpuMemTemp, Brightness, NightLight,
                         # Clipboard, WifiState, Wallpaper
  util/                  # format.js helpers
```

Key mechanics:
- **Hot reload**: quickshell reloads on save — iterate live in the session.
- **Multi-monitor**: `Variants { model: Quickshell.screens }`, per-screen
  bar; workspaces filtered by `I3.monitorFor(screen)`.
- **Lock trigger**: `bindsym $mod+P exec quickshell ipc call lock lock`;
  swayidle: `timeout 300 'quickshell ipc call lock lock'` + `timeout 330
  'swaymsg output "*" dpms off'` + resume on unlock/input.
- **PAM**: bundled `passwd` service file in `assets/pam.d` (like caelestia)
  so no system PAM edits needed. Password only (no fingerprint).
- **Wallpaper blur**: LockSurface renders the same `wallpaper.jpg` swaybg
  uses (path from the `Wallpaper` service), stretched per-screen (fill),
  behind a `MultiEffect` blur + gruvbox dark overlay. No screencopy → no
  warm-up trick, no capture flakiness.

## Phases (each verified before next)

1. **Bootstrap** — install `qt5compat qtsvg qtimageformats`; create stow
   package with minimal shell.qml + gruvbox Theme.qml; update sway autostart
   (stop waybar/waybar_top/rofi; start quickshell); verify hot reload; verify
   sway supports ext-session-lock (`sway --version` ≥ 1.8).
2. **Right bar** — workspaces, taskbar, clock, cpu/mem/temp, battery, tray,
   network ssid, volume, mpris, language + calendar/audio/power popups.
   → waybar fully removed from session here.
3. **Launcher** — drun with fuzzy search, `$mod+d`, ESC close.
4. **Notifications** — NotificationServer + popup (urgency styling) + center.
5. **OSD + polkit agent.**
6. **Lock screen + swayidle** — PAM, wallpaper blur (MultiEffect), IPC,
   dpms; `$mod+P`.
7. **Extras** — control center, clipboard, network menu, night light,
   screenshot picker. Replace grimshot keybind.
8. **Cleanup** — drop waybar/waybar_top/swaylock/rofi stow packages, prune
   autostart, update README + install.md, document quickshell version pin.

## Risks & notes

- Quickshell is pre-1.0: breaking changes on upgrades — pin `0.3.0` in
  install.md, configs in git.
- Lock shows the wallpaper image (blurred), not a live screen capture —
  deliberate: avoids screencopy warm-up races and NVIDIA flakiness (this
  machine runs sway with `--unsupported-gpu`) entirely. Trade-off: no
  live snapshot of the desktop behind the lock; fine since swaybg's
  wallpaper is already the desktop background.
- ext-session-lock input: media keys with `--locked` continue to work
  (verify live).
- Keyboard layout: lock screen must render layouts correctly (es/us) — PAM
  reads raw keys, no issue; visual indicator optional.
- `Quickshell.I3` tracks workspaces/monitors; the desk scheme (0a..9c) stays
  sway-side (scripts untouched); bar shows workspace `name` (e.g. "1a").
- Tray needs a StatusNotifierWatcher — provided by the SystemTray service
  (no snixd needed).
- Clipboard manager: watch via `wl-paste --watch` (wl-clipboard) into a
  ring buffer service.

## Phase 1 log (2026-08-13, done)

- Installed: none needed (qt6-svg already present; qt6-5compat/
  qt6-imageformats optional — user runs `sudo pacman -S qt6-5compat
  qt6-imageformats` if wanted; MultiEffect avoids the 5compat dependency).
- Created stow package `quickshell/` (shell.qml + Theme.qml + bar/RightBar.qml).
- Autostart: waybar line replaced with `exec_always sh -c 'pkill -x waybar
  2>/dev/null; pkill -x quickshell 2>/dev/null; sleep 0.2; exec quickshell'`.
- **Verified live**: sway 1.12 supports ext-session-lock ✓; quickshell bar
  renders flush at the right edge of DP-1 (focused monitor); sway reload
  restarts quickshell cleanly as a sway child; waybar is gone.
- **Quirk 1 — exclusive zones**: while waybar was still running, the
  quickshell bar rendered *left of* waybar (waybar owns the right-edge
  exclusive zone). Not a bug; gone with waybar.
- **Quirk 2 — hot reload state can go stale** (audited 2026-08-13): a
  purely structural edit (adding a window) reloads and maps fine in
  isolation (verified), and property-level edits reload fine. But after a
  mid-session hot reload of the launcher internals, the live session's
  window/grab state went inconsistent (focus didn't restore on close) —
  a fresh start fixed it. Workflow: prefer a restart (`pkill -x
  quickshell` + `swaymsg reload`) after significant edits; hot reload is
  fine for styling.
- **Pattern that works**: file-root PanelWindow or Variants delegates on
  `Quickshell.screens` map on fresh launch. Bars/popups will all follow
  the Variants-per-screen pattern.
- QS_NO_RELOAD_POPUP=1 set via pragma (no toast on every reload).

## Phase 2 log (2026-08-13, done)

Full right bar live: desk pills, taskbar, mpris, cpu/mem/temp, volume,
backlight, network, layout, tray, battery, clock, power + calendar/audio/
power popups with backdrop dismissal. Waybar fully retired.

Landmines found and worked around (all documented in code comments):

1. **ObjectModel has `.values`, not `.length`** — all model iteration uses
   `.values` (reactive).
2. **Native (C++) method calls don't track their internals in bindings** —
   a QML *JS* function call *is* tracked (verified 2026-08-13: a bare
   `lookup()` reading a property re-evaluates on change). What is *not*
   tracked is a native method's internal reads — e.g. `I3.monitorFor(s)`
   in a binding evaluates once, so it's guarded by a tracked
   `I3.monitors.values.length ?` ternary. The old "pass every model as an
   argument" rule was over-broad but harmless where used.
3. **sway `get_workspaces` has no node trees** — the taskbar originally
   parsed `swaymsg -t get_tree` for windows; that was later replaced by
   the native `ToplevelManager` (wlr-foreign-toplevel, see Taskbar.qml —
   no swaymsg subprocesses). Workspaces themselves come from
   `Quickshell.I3` (desk pills).
4. **DesktopEntries scan is async** (queued completion after first access)
   — icon lookups track `DesktopEntries.applications.values`.
5. **PopupWindow works on wlr-layer-shell — xdg_popup GRAB needs input
   first** (audited 2026-08-13, see below): a PopupWindow anchored to a
   PanelWindow attaches cleanly as an xdg_popup child of the layer
   surface. The earlier "popup is not an xdg_popup" failure only happens
   for the *grabbing* variant: with `grabFocus: true` and no prior input
   on the parent, Qt can't create a grabbing popup ("Failed to create
   grabbing popup… parent window has received input" — the xdg-shell
   grab needs an input serial) and quickshell's fallback warning fires.
   Popups opened by real clicks (the norm) get that serial and attach
   fine. Dismissal is app-side via `PopupManager` (single-popup-at-a-
   time, toggle, hover-popup close), complementing the native grab.
   Note: the old "LayerPopup + PopupBackdrop" design described below is
   gone — AnchoredPopup *is* a PopupWindow.
6. **Only layer-surface windows (PanelWindow) map as file-root or
   Variants delegates** — xdg_popup windows (PopupWindow) map fine as
   direct children (the calendar/audio/power popups are direct children
   of the bar PanelWindow and work). A PanelWindow child does not map as
   its own surface — that's why the bars and the launcher are Variants
   delegates on `Quickshell.screens`.
7. **Create windows eagerly, toggle visibility** — popups are declared
   in the bar scene from the start (no lazy creation) and shown via
   `showAt` (visible: true) / `hide` (visible: false). Lazy window
   creation races are real (nondeterministic mapping); eager creation
   sidesteps them. PanelWindows resize reactively from
   implicitWidth/implicitHeight.
8. ~~Inline components can't see root props~~ — **FALSE** (audited
   2026-08-13): inline components can reference file-root ids; PowerMenu's
   rows already do (`root.armedAction`).

Remaining: exit-confirm uses the power menu (swaynag removed). Note: the
audio menu now lists hardware sinks from Pipewire (old audio_menu.sh is
gone). gammastep-indicator is dead (no tray app); night-light toggle comes
in phase 7.

## Phase 3 log (2026-08-13, done)

Launcher live: drun with fuzzy search, `$mod+d` toggles it, Enter launches,
Esc / click-outside closes. Rofi retired.

- `services/LauncherState.qml` (new singleton): `open` state + `IpcHandler
  target "launcher"` with typed functions `toggle()` / `open()` / `close()`
  (the 0.3.0 IPC way — functions with explicit signatures, not
  onSignalTriggered). sway: `set $menu quickshell ipc call launcher toggle`.
- `popups/Launcher.qml` (new): one fullscreen transparent PanelWindow per
  screen (Variants delegate, shell.qml). Only the focused monitor's
  instance is visible (`I3.monitorFor(screen).focused`, guarded by
  `I3.monitors.values.length`). Centered gruvbox card: search input, 8-row
  results window, empty state, footer hint.
- **Keyboard grab**: PanelWindow has no `grabFocus`; the wlr-layer-shell
  attached property does it — `WlrLayershell.keyboardFocus:
  WlrKeyboardFocus.Exclusive` (import `Quickshell.Wayland._WlrLayerShell`).
  Grab is active while the surface is mapped; focus returns to the session
  on close (verified via `swaymsg -t get_tree` focused-node cycling).
- **Landmine 9 root-caused — `required property var modelData` kills
  `index`** (verified 2026-08-13): with the `required` declaration,
  `index` is `ReferenceError` in delegates (ListView *and* Repeater);
  with implicit `modelData` (no `required`), `index` works fine.
  Refactored the launcher to use native `index` + `ListView.isCurrentItem`
  + plain `currentIndex`, dropping the entry-object-identity selection
  machinery. (The old note below — Repeater/Column slice windowing — was
  superseded by the native ListView from the efficiency review.)
- **Fuzzy scorer**: per-token subsequence over name/generic/keywords/
  categories/exec; scores consecutive runs and word starts, bonus for
  name-prefix; `noDisplay` entries excluded; sort by score then name.
  Unit-tested in node before embedding (`/tmp/scorer_test.js`, 10/10).
- `TextInput` here has no `placeholderText`/`placeholderTextColor` (Controls
  only in this Qt) — dropped, the search glyph carries the affordance.
- Focus arming: `focus: true` on the input + `Qt.callLater(forceActiveFocus)`
  on open (deferred past surface mapping).
- **Verified live**: clean load (0 errors); `ipc show` lists the handler;
  open/toggle/close all exit 0; seat focus cycles toplevel ↔ launcher
  (launcher has the keyboard while open); sway reload validates the new
  `$menu`.
- Note: fixed two pre-existing WIP errors that blocked the whole shell from
  loading — duplicate `onPressed` handlers on MprisWidget's and Taskbar's
  MouseAreas (merged; MprisWidget kept its left-click togglePlaying).

## Phase 4 log (2026-08-13, done)

Notification daemon + popups + center live (replaces the missing notification
piece; nothing was running before):

- `services/Notifications.qml` (new singleton): owns the `NotificationServer`
  (org.freedesktop.Notifications, verified registered on the session bus),
  keeps a capped (50) history for the center, drives popup visibility and
  per-urgency timeouts, tracks unread, DND (critical still interrupts), and
  exposes the IPC entry point (`quickshell ipc call notifications
  toggle|open|close|test|dnd|clear|count`).
- `popups/NotificationPopup.qml` (new): one top-right PanelWindow per screen
  (Variants in shell.qml), just left of the bar; ≤ 3 popups, newest on top;
  `exclusionMode: Ignore` (transient, never shrinks tiling area). Rows are
  routed to the screen focused at arrival (I3.focusedMonitor → Screen by
  name) so popups don't duplicate or chase focus.
- `popups/NotificationRow.qml` (new): shared card for popup + center — app
  icon (name→theme/path→file), app+summary, body (wrap/elide), optional
  image + action buttons (action.invoke() — the server closes the
  notification afterwards unless `resident`), close ✕. Urgency styling:
  critical = red border + never auto-dismisses; normal / low auto-dismiss
  after 7s / 5s (app expire_timeout honored when > 0). Hover pauses the
  popup's dismissal timer; clicking a popup opens the center. Transient
  notifications vanish entirely when their popup ends.
- `popups/NotificationCenter.qml` (new): fullscreen transparent PanelWindow
  per screen (launcher pattern — focused monitor only, exclusive keyboard
  focus, Esc/backdrop close), card anchored right next to the bar: header
  (DND toggle + clear-all), scrollable history, empty state. Opening marks
  everything read and ends active popups.
- `bar/NotificationsWidget.qml` (new): bell glyph between battery and
  clock, red unread badge (hidden in DND), click toggles the center.
- sway: `$mod+n` → `quickshell ipc call notifications toggle` (bell also
  toggles it). No libnotify on this machine — `test()` (and verification)
  use `gdbus call … Notify` with the full `susssasa{sv}i` signature.

Verified live (logs + ipc + D-Bus round trips + user visual check): clean
load; server registered; `ipc show` lists the handler; `test()` / raw
`gdbus` Notify round-trip (id, count, `[notifications]` log lines); popup
auto-dismiss after 5–7s while history stays (`count` unchanged); app-side
`CloseNotification` removes from history; DND suppresses popups but still
stores; `clear` empties everything; center toggle/close clean. User-confirmed
visually: popup text/styling, critical red + persistence, ✕ dismissal, hover
pause, center rows + DND/clear, bell badge, `$mod+n`. Capabilities
advertised: persistence, body, body-markup, actions, icon-static.

Landmines found and worked around (this phase):

10. **`screen`-dependent bindings loop on PanelWindow map/unmap** —
    `shown = Notifications.popups.filter(w => w.screen === root.screen)`
    bound the popup's visibility to the window's own `screen` property;
    mapping/unmapping re-evaluated `screen`, feeding back into
    `shown` → `visible` ("Binding loop detected for property shown").
    Fixed with a one-time `Component.onCompleted` snapshot
    (`routeScreen`) — never read the window's `screen` inside a
    visibility-dependent binding.
11. **`null` vs `undefined` in delegate guards** — QML delegates are
    instantiated with `wrapper`/`modelData` transiently undefined, so
    `notif = wrapper ? wrapper.notification : null` could yield
    `undefined` and `x !== null && x.prop` then threw "Cannot read
    property … of undefined". Fixed: `wrapper && wrapper.notification`
    (both falsy → null) plus `!== null` guards everywhere.
12. **`notifications`/`popups` are plain JS objects, not QObjects** — the
    service stores lightweight wrapper objects ({notification, screen,
    timeoutMs, …}); all list mutations reassign the whole array so
    popup/center bindings re-evaluate (landmine 2 pattern). The wrapped
    `Notification` itself stays a QObject, so its property change signals
    keep rows reactive (e.g. app replaces/replacesId updates in place).
13. **Notification objects die on close** — the server deletes a
    Notification after `closed` fires (dismiss/expire/CloseRequested/
    action invoke). The service nulls the wrapper's reference on removal
    and never touches a closed notification (idempotent removeWrapper).
14. **`required property var modelData` on a Variants delegate shadows
    `modelData` in *nested* Repeater/ListView delegates** (root-caused via
    throwaway configs): a file-component delegate (`NotificationRow {
    wrapper: modelData }`) resolved `modelData` to the outer window's
    screen — rows rendered empty and ✕/actions discarded the wrong
    object. Plain *inline* delegates (`delegate: Item { … }`) resolve
    correctly; inline components do NOT (they're compiled like file
    components). Fix: inline wrapper delegate that resolves `modelData`
    and passes it down by property. (The launcher was unaffected — its
    delegate is inline, and it never reads `modelData` for actions.)
15. **Column+Repeater implicit sizing is unreliable** — a Column whose
    only child is a Repeater reports implicitHeight 0 (its implicit size
    is not recomputed when Repeater-created Items appear, even with
    explicit implicitHeight on the wrappers). The popup window therefore
    collapsed to zero height. Fix: ListView with `height: contentHeight`
    (sizes to realized delegate heights, verified: -1 → 308 → 158
    settles correctly; ≤ 3 rows are always realized).

Note: the qslog rotates at ~64KB and the threaded logger can interleave
lines — for long sessions, grep the newest instance under
`/run/user/1000/quickshell/by-id/`. (console.log also lands in the
session's stdout log, e.g. `~/.local/state/ly-session.log`, which is the
complete copy — the qslog mirror can drop lines.)

## Phase 5 log (2026-08-13, done)

OSD (volume via Pipewire watch, brightness via sysfs poll) + polkit
authentication agent live. No sway config changes needed — the OSD is a
pure observer and the polkit agent self-registers on the system bus.

- `services/Brightness.qml` (modified): availability now requires a real
  `backlight`-class device (probe of `/sys/class/backlight`). The old code
  trusted brightnessctl's default-device selection, which falls back to
  keyboard LEDs when no backlight exists — on this desktop that lit up a
  phantom 0% widget (now gone from the bar). Poll 2s → 500ms so the OSD
  detects changes promptly.
- `services/Osd.qml` (new): singleton OSD state — kind (volume/brightness),
  level, muted, routed screen. Volume is event-driven via Pipewire
  (`volumesChanged`/`mutedChanged` on `defaultAudioSink.audio` with a
  `PwObjectTracker`; official volume-osd example pattern). Brightness is
  poll-detected by watching `Brightness.percent`. Startup/hot-reload
  values are suppressed (armed flag). Identical re-shows (a quickshell
  write emits the Pipewire signal locally AND on the server echo) only
  re-arm the timer — no log spam.
- `popups/OsdPopup.qml` (new): one bottom-center PanelWindow per screen
  (Variants in shell.qml); only the routed screen's instance shows.
  Layer-shell spec: bottom anchor + no horizontal anchor → centered.
  Empty input mask (`mask: Region {}`) so clicks pass through.
- `services/Polkit.qml` (new): owns `PolkitAgent` (default path
  `/org/quickshell/Polkit`), exposes active/flow/registered, submit()/cancel().
- `popups/PolkitDialog.qml` (new): fullscreen PanelWindow per screen,
  focused-monitor only (launcher pattern + exclusive keyboard grab).
  Card: icon (iconPath w/ shield fallback), message, prompt, password
  TextInput (echo when `responseVisible`), error/info text, identity
  selector (only when polkitd offers > 1 — inline delegate per landmine
  14), Cancel/OK buttons. Enter submits, Esc cancels; failed attempts
  clear + refocus (the flow keeps itself alive with a fresh session).
- `shell.qml` (modified): OsdPopup + PolkitDialog Variants added.

Verified live: clean loads; OSD fires on wpctl volume/mute changes; bar
widget scrolls dedupe to one log line; polkit agent registered (`[polkit]
agent registered: true`), pkexec requests route to it (polkitd journal +
`[polkit] request active` logs), dialog appears, user cancel → pkexec
"Request dismissed", wrong password → red error + retry, correct password
→ `pkexec --disable-internal-agent id` prints uid (user-confirmed).
PAM needs no system edits: `/usr/lib/pam.d/polkit-1` exists (includes
system-auth) — the bundled pam.d trick is only needed for the lock screen
(phase 6). Brightness OSD is inert here (no backlight); the phantom
0% brightness widget is gone from the bar.

Landmines found and worked around (this phase):

16. **brightnessctl has no monitor/watch mode.** `brightnessctl -m monitor`
    is parsed as the `max` operation (first letter 'm') and prints
    max_brightness — verified against the installed 0.5.1 binary and the
    master source, which has no monitor subcommand at all. "Brightness via
    sysfs poll" (the plan's choice) is the only event source.
17. **Unknown property reads in bindings don't error — they yield
    undefined.** The OsdPopup progress bar and percent text used
    `root.level` (no such property on PanelWindow) → "undefined%" text and
    a NaN fill width. QML silently propagates undefined. Fix: reference the
    singleton (`Osd.level`) everywhere in per-screen delegates.
18. **Polkit success signal vs flow teardown ordering.** On SUCCESS the
    agent nulls `flow` BEFORE emitting `authenticationSucceeded`
    (AuthFlow::completed → mRequest->complete → finishAuthenticationRequest
    → bActiveFlow=null, then emit), so a `Connections { target: flow }`
    binding detaches just before the signal fires and the handler is never
    called. Failure keeps the flow alive (fresh session restarted
    internally), so the failure path worked fine via Connections. Fix:
    JS-connect on the flow object in `onFlowChanged`.
19. **`?.` in a Connections target yields undefined** → "Unable to assign
    [undefined] to QObject*" + spurious "no signal matches" warnings.
    Use an explicit ternary that yields null.
20. **faillock is a landmine for unattended auth testing.** A polkit
    conversation that ends without authenticating counts as a failed PAM
    auth; three unattended pkexec tests (killed processes / nobody typed)
    tripped `deny=3` → 10-minute account lock that also takes down
    sudo/su/login (they all include system-auth). Debugging "password
    always fails"? Check `faillock --user $USER` first. Never run
    unattended PAM-triggering tests; the phase-6 lock screen (PAM) will
    hit the same counter — password-only tests must be interactive.
21. **pkexec kills itself when its parent dies** (`PR_SET_PDEATHSIG`) —
    launching pkexec from a tool/shell that exits cancels the polkit
    conversation, so the dialog appears to "self-dismiss". Keep the
    parent alive, or let the user run pkexec from their own terminal.

Also: the right bar was reported missing once mid-session; a clean
restart restored it (phase-1 quirk 2 pattern — hot-reload window state
can go stale; no code change needed). One OSD bug fixed live (the
undefined-property issue above) caused an automatic hot reload that
re-registered the polkit agent mid-test — don't edit files while a polkit
conversation is on screen.

## Phase 6 log (2026-08-14, done)

Lock screen + swayidle live (replaces swaylock; the PowerMenu Lock row and
`$mod+P` now work — the IPC target exists). No system PAM edits needed.

- `services/Wallpaper.qml` (new singleton): one-time startup probe for the
  sway wallpaper (`~/.config/sway/wallpaper.{jpg,png}`, first readable
  wins), exposes `path`/`url` for the lock blur. Lock.qml touches it at
  startup so the probe isn't deferred to the first lock (lazy singleton
  instantiation would otherwise delay the first lock's background by one
  probe round-trip).
- `lock/Pam.qml` (new): PamContext with the bundled service `passwd` under
  `lock/assets/pam.d` (`auth required pam_unix.so` — password only, no
  fingerprint, and deliberately NO pam_faillock: a wrong password on the
  lock screen can never trip deny=3 / lock the account; swaylock's
  system-auth chain has that hazard). Shared state (`currentText` /
  `unlockInProgress` / `showFailure`) lives here so every per-screen
  surface mirrors the same buffer. Buffer cleared on completion, not on
  respond (official-example behavior — a follow-up prompt keeps the text).
- `lock/Lock.qml` (new): WlSessionLock (locked stays false at startup —
  only IPC/idle/power-menu engages it) + per-screen WlSessionLockSurface
  delegate + IpcHandler `target: "lock"` with `lock()`/`unlock()`/
  `isLocked()`. PAM success → locked=false + one `swaymsg output "*" dpms
  on` (covers IPC unlocks; typing already fires swayidle resume).
- `lock/LockSurface.qml` (new): full-screen per monitor — blurred wallpaper
  (Image in a `layer.enabled` Item + MultiEffect blur `0.4/40`) + gruvbox
  dark0 overlay, centered lock glyph / HH:MM clock (SystemClock) / date /
  password field (shared-buffer binding, Enter submits, Esc cancels+
  clears, failure shows in urgent red, refocus re-armed on re-enable).
- `shell.qml`: `Lock {}` added (import qs.lock).
- sway: `bindsym $mod+P` now `quickshell ipc call lock lock` (swaylock
  dropped); autostart gains `exec swayidle -w timeout 300 'quickshell ipc
  call lock lock' timeout 330 'swaymsg output "*" dpms off' resume
  'swaymsg output "*" dpms on'` (plain `exec`, not exec_always — a sway
  reload must not spawn a second swayidle; multi-line backslash
  continuation verified in sway 1.12 source: getline_with_cont).
- install.md: swayidle added to the quickshell deps.

Verified live: clean loads; `ipc show` lists the handler; lock →
`[lock] state: locked` + `[lock] compositor secure: true` (compositor
confirmed all screens covered) → unlock → secure false; wallpaper probe
logs `path: /home/marc/.config/sway/wallpaper.jpg`; swayidle parses the
args and runs in-session (started via `swaymsg exec` — the autostart line
only fires at next login). **User-confirmed visually + interactively**: the
full password flow — lock, type password, `Authenticated successfully.`
(session log), unlock — plus the blurred wallpaper background and clock.

Landmines found and worked around (this phase):

22. **`root.<id>` never resolves — ids are not properties.** `root.pwInput`
    (id access through the file-root object) is `undefined` in handlers;
    only bare ids resolve (verified with throwaway configs: root handler,
    sibling handler, own handler — all fail on `root.<id>`, all pass on
    bare `<id>`). Declared properties (`root.pam` where pam is a declared
    property) work fine. Fixed in LockSurface (pwInput accesses) and
    Pam.qml (pamContext accesses); the codebase's bare-id convention
    (searchInput/pwInput/resultsList) is the rule going forward.
23. **Outer id colliding with a delegate's `required property` resolves to
    the instance's own unset property inside a Component.** Lock.qml's
    `Pam { id: pam }` + `LockSurface { pam: pam }` → binding loop on
    `pam` + null everywhere (the surface delegate is a Component; the
    same-named initializer binds to the not-yet-assigned required
    property instead of the outer id). Distinct names (id `auth`, property
    `pam`) fix it — same shadowing family as landmine 14.
24. **`WlSessionLock.setLocked(true)` never emits lockStateChanged** — the
    manager only emits it on unlock; the compositor confirmation is the
    separate `locked`/secure signal. Logging on the target-state property
    (`onLockedChanged`) gives symmetric lock/unlock lines.
25. **Directory-imported `pragma Singleton` files don't behave like module
    singletons in throwaway configs** (`import "svc.qml" as S` — never
    instantiated, onCompleted never fires). In the real `qs.services`
    module singletons DO instantiate and run onCompleted (CpuMemTemp's
    1 Hz poll proves it). Only affects /tmp repros, not the shell.

Notes: restarting quickshell while the session is locked leaves the
compositor's lock in place (ext-session-lock security — no sway IPC can
release it; the session stays locked until TTY login). Don't do it. The
`--locked` media keys were already present in the sway config; their
behavior under the quickshell lock needs the user's confirm (next
interactive session) — sway handles them independently of the lock
surface.

## Phase 7 log (2026-08-14, done)

Extras live: control center, clipboard history, network menu, night light,
screenshot picker. grimshot keybind replaced. gammastep-indicator retired
(the sway autostart line is gone; the NightLight service owns gammastep).

- `services/ControlCenter.qml` (new): open state + IpcHandler
  `controlcenter` (toggle/open/close).
- `services/Clipboard.qml` (new): history ring (cap 20) watched via
  `wl-paste --watch` + a `cat; printf '\036'` command (ASCII RS delimiter,
  SplitParser splitMarker — verified with a stub that one clipboard change
  == exactly one chunk, multi-line intact). Availability probed once
  (`command -v wl-paste && command -v wl-copy`); without wl-clipboard the
  ring is inert and the popup shows a hint. Copies go through argument-
  based `wl-copy` (no shell, no injection); the watch echo is deduped.
  IpcHandler `clipboard` (toggle/clear/count).
- `services/NightLight.qml` (new): gammastep wrapper. Apply model verified
  against gammastep 2.0.11 (`-p` print mode): enabled → `gammastep -O <K>
  -P -b <day>:<night>` (one-shot, exits immediately — no daemon), disabled
  → `gammastep -x`. State (enabled/temperature/day/night brightness)
  persists to `~/.local/state/quickshell-nightlight` (JSON; $HOME via
  `Quickshell.env()` — verified 2026-08-14; written on change, read once
  at startup). IpcHandler `nightlight` (toggle/on/off). The control center
  hosts toggle + temperature (1000–6500K) + day/night brightness sliders
  (gammastep -b DAY:NIGHT).
- `services/WifiState.qml` (new): native NetworkManager wrapper — no nmcli.
  `wifiDevice` (first DeviceType.Wifi), networks (tracked .values),
  wifiEnabled (rfkill, writable), sortedNetworks (connected first, then
  signal), connect/disconnect via `Network.connect()` / `connectWithPsk()`
  / `disconnect()` (known → connect(); open/OWE → connectWithPsk(""); other
  secured → inline PSK row), connectionFailed wiring (NoSecrets re-opens
  the PSK row), scanner refcount (scan only while a network UI is visible
  — `useScanner(true/false)` on popup show/hide).
- `services/Screenshot.qml` (new): grim backend (the plan deliberately
  avoids ScreencopyView). `capture(geometry)` hides the picker first —
  **grim composites layer-shell surfaces, so the overlay would appear in
  the shot otherwise** — spawns `sh -c 'mkdir -p …; grim -g "$1" - > file
  && wl-copy-if-present && echo "$file"'`, notifies through our own daemon
  (gdbus, image-path hint for the thumbnail). IpcHandler `screenshot`
  (pick/full/toggle).
- `popups/ControlCenter.qml` (new): fullscreen PanelWindow per screen
  (focused monitor only, launcher pattern). Right-edge card next to the
  bar, Flickable-scrollable: volume (Pipewire write, mute switch),
  brightness (brightnessctl write, debounced 120ms), night light (toggle +
  temp + day/night brightness sliders), network (shared NetworkSection),
  power (shared PowerSection). Esc/backdrop close; wifi scanner active
  while open.
- `popups/NetworkMenu.qml` (new): bar-anchored quick menu (network widget
  click) with the shared NetworkSection; scanner refcount on show/hide.
- `popups/NetworkSection.qml` (new, shared): wifi toggle + rescan + up to
  8 AP rows (signal icon, lock, ssid, check/spinner) + inline PSK row +
  error line + ethernet rows. Inline delegates binding `net` by index
  (landmines 9/14 — no `required property var modelData`).
- `popups/ClipboardPopup.qml` (new): launcher-style fullscreen popup
  (focused monitor only): search + history list, click copies + closes, ✕
  removes one, clear-all, Esc/backdrop close, empty states (incl. the
  wl-clipboard hint).
- `popups/ScreenshotPicker.qml` (new): fullscreen overlay per screen, ALL
  instances visible while open (drag on any screen). Dim + selection
  border (4 rects, no masks), size label, hint pill. Drag → area capture;
  click → fullscreen of that screen; Esc cancels. Only the focused
  monitor's instance grabs the keyboard.
- `popups/ToggleSwitch.qml`, `popups/ControlSlider.qml` (new, shared):
  gruvbox pill switch + slider (drag-safe: handle follows the mouse while
  pressed, binding takes over on release).
- `popups/PowerSection.qml` (new): power actions extracted from PowerMenu
  (lock/logout/suspend/reboot/shutdown, two-step confirm) — now shared by
  the power popup and the control center (`actionTriggered` signal lets
  embedders close themselves). PowerMenu is a thin AnchoredPopup wrapper.
- `bar/NetworkWidget.qml`: click opens the NetworkMenu popup (was
  display-only).
- sway: Print → `$screenshot` (area picker), Shift+Print → fullscreen,
  `$mod+Shift+c` → control center, `$mod+Shift+v` → clipboard (new $vars in
  0variables); grimshot bind and the gammastep-indicator autostart line
  removed. install.md: + gammastep dep note, wl-clipboard now required for
  the clipboard manager (installed this session).

Verified live (fresh restart via `swaymsg reload`, 0 errors):
- `ipc show` lists all 7 handlers (controlcenter/clipboard/nightlight/
  screenshot + lock/launcher/notifications).
- Clipboard ring: copies captured (log), dupes deduped (count stable),
  multi-line kept as one entry, `count` IPC works; wl-paste --watch runs
  as a long-lived child.
- Popups open/close cleanly and grab/restore keyboard (swaymsg get_tree:
  no focused node while open = layer surface has the seat; focus returns
  to the toplevel on close — same check as phase 3).
- Fullscreen screenshot: valid 1920×1080 PNG saved to
  ~/Pictures/Screenshots and a daemon notification fired
  (`[notifications] qs-screenshot: Screenshot taken`). One early capture
  produced an empty file — that ran mid-hot-reload (the process was
  spawned during reload teardown); clean restarts are reliable.
- Night light: on/off round-trip writes the state file
  (`{"enabled":…,"temperature":4000,"day":1,"night":0.7}`) and applies
  gammastep; startup read + apply verified.
- Network state native module: devices populate async, wifiEnabled
  tracked, DeviceType.Wifi=1/Wired=2 (no wifi hardware on this desktop —
  the wifi UI hides; ethernet rows render).

Landmines found and worked around (this phase):

26. **Quickshell.clipboardText cannot watch the clipboard** (verified
    2026-08-14, two throwaway configs): the notify `clipboardTextChanged`
    fires ONLY on self-writes (the C++ side never wires QClipboard's
    dataChanged into `onClipboardChanged` — that virtual is called
    nowhere in the 0.3.0 source), and cross-instance reads of external
    offers return empty. Writing works in-process. The plan's wl-paste
    watch is the only reliable source — the native property is a trap
    for managers.
27. **`wl-paste --watch` rejects `--` before the command.** getopt treats
    `--` as `--watch`'s required argument and errors ("Expected a
    subcommand instead of an argument after --watch"). The command must
    follow `--watch` directly: `wl-paste --type text/plain --watch sh -c
    'cat; printf "\036"'` (verified against wl-clipboard 2.3.0 source +
    binary). The RS delimiter survives SplitParser's chunking.
28. **Process `running: <binding>` does start processes on the binding
    flip — but only after load** (root-caused in the 0.3.0 source):
    `startProcessIfReady` early-returns while `isPostReload` is false,
    so a `running: true` binding set during config load is deferred to
    the post-reload hook. Fine for watchers whose `running` flips after
    load (our availability-probe pattern); don't rely on a load-time
    `running: true` binding to start something synchronously.
29. **Process `onExited` fires for watch-mode subprocess deaths too** —
    `wl-paste --watch` exits 1 on bad args (landmine 27), which the
    watcher's parent process reports; the first version of the watcher
    silently died until the args were fixed. Check `pgrep -af wl-paste`
    (or the exit code) after changing watch commands.

Notes: the old gammastep-indicator tray app + its gammastep daemon were
still running this session — killed (`pkill -f gammastep-indicator;
pkill -x gammastep; gammastep -x`) before testing night light; gone on
next login via the removed autostart line. The screenshot picker's click-
for-fullscreen also covers the non-focused screen (per-screen windows,
screen-relative coords — grim -g is output-layout global, verified
byte-identical to `grim -o`). Control center wifi section and NetworkMenu
are untestable live here (no wifi hardware); the native API paths were
verified against the docs + qmltypes, and the UI hides gracefully
(machine-agnostic per the plan).


## Phase 7 follow-up (2026-08-14, user-driven rework)

Two user-driven changes after the phase 7 log:

1. **Control center removed** — the user prefers one popup per feature.
   The control center's sections moved to their own bar-anchored popups:
   - `popups/AudioMenu.qml`: + volume slider + mute switch (Pipewire
     writes, no spawns) above the existing sink list.
   - `popups/BacklightPopup.qml` (new): brightness slider
     (brightnessctl writes, 120ms debounce); `bar/BacklightWidget.qml`
     click opens it (was a 5% step), wheel unchanged.
   - `popups/NightLightPopup.qml` (new) + `bar/NightLightWidget.qml`
     (new, moon glyph turns warm when active): toggle + temperature +
     day/night brightness sliders. Sliders update state live but only
     restart the gammastep daemon on RELEASE (a restart is a ~50ms
     neutral flash — see below).
   - Deleted `popups/ControlCenter.qml` + `services/ControlCenter.qml`;
     sway `$mod+Shift+c` + `$controlcenter` removed (key is free).

2. **gammastep integration fixed** — the phase-7 one-shot approach was
   fundamentally broken on wlr. Root-caused live (2026-08-14) and
   rewritten as a single-daemon design:

   - **`gammastep -O` and `-x` never exit** — both print "Press ctrl-c
     to stop..." and stay connected to the compositor forever.
   - **wlr-gamma-control allows exactly ONE owner per output.** Every
     later process reports "Zero outputs support gamma adjustment" but
     hangs anyway. The phase-7 code spawned one process per change;
     the user ended up with ~30 hung processes and no visible change
     (only the first held gamma, and its values were stale).
   - **No config file watching, no SIGHUP reload** (verified in the
     2.0.11 source: the config is read once at startup; SIGUSR1 only
     toggles disable). The "elegant real-time" answer: ONE long-lived
     daemon, values changed by restarting it (kill + exec), toggle off
     by killing it (sway reverts the LUT when the client disconnects).
   - The daemon is spawned detached from quickshell (survives restarts)
     and sway does NOT run gammastep (one owner only — verified: two
     daemons = second hangs). Apply: `gammastep -O <K> -P -g 1.0 -b
     <d>:<n>` (constant temperature, -b day/night by solar elevation,
     -g 1.0 neutralizes the user config's gamma so the brightness
     sliders own dimming; location + method come from the user's
     gammastep config). Disabled = pkill (no process left).
   - **Cosmetic quirk:** gammastep NUL-splits the `-b`/`-t` argv string
     in place while parsing `DAY:NIGHT`, so `ps` shows `-b 0.42 0.63`
     — the colon became a NUL. Values were always parsed correctly;
     don't "fix" the args based on ps output.
   - Slider UX: apply on release (one restart per drag), not per tick
     (restarting per tick flickers — the LUT resets during the ~50ms
     kill/exec gap).

Verified live: toggle on → exactly one persistent gammastep process
holding gamma; idempotent re-toggle; toggle off → zero processes (LUT
reverts); startup-apply of persisted state spawns the daemon with the
stored values; clean reload with 0 errors after the control center
removal.


   - **Popup row width landmine (2026-08-14):** every child of a popup's
     PopupShell content column needs an explicit `width: parent.width`.
     Rows that omit it collapse to 0-wide while the window is unmapped
     (the implicit-width chain doesn't resolve hidden) — the night light
     popup's sliders were invisible until each SliderRow got an explicit
     width (verified: hidden 280×41 → shown 280×213, and the same pattern
     is what makes PowerMenu/AudioMenu rows work). Landmine 15's "implicit
     sizing unreliable" applies to height too: explicit heights + explicit
     widths on every row; only Text/SectionLabel can rely on implicit.


3. **Night light removed; gammastep-indicator restored** (user decision
   after the daemon rework still showed multi-output races + slider
   drift). The research the user asked for came up empty — there is no
   established live-adjustment integration for gammastep:
   - gammastep master is 2.0.11 (same as installed): no DBus control, no
     config watching, no SIGHUP reload; SIGUSR1 toggles the filter only
     (signals.c). The only established integrations are the indicator
     (spawn `gammastep -v` daemon, SIGUSR1 toggle, values from config)
     and ekremx25's `-O` one-shot (broken on wlr — verified: `-O`/`-x`
     never exit and later clients get "zero outputs support").
   - wlroots source (types/wlr_gamma_control_v1.c): when the gamma
     control client disconnects, `set_gamma` is emitted with a NULL
     table — **sway resets the LUT**. The daemon must stay alive, and
     every value change needs a restart whose kill→exec gap races
     per-output ownership ("sometimes only one output changes").
   - The "slider drift while pressed" report was not root-caused from
     source; given no established pattern to match and the user's
     explicit fallback, the component was removed instead of debugged.
   Removed: services/NightLight.qml, popups/NightLightPopup.qml,
   bar/NightLightWidget.qml, the `nightlight` IPC target; sway autostart
   restores `exec_always sh -c 'pkill -x gammastep; exec
   gammastep-indicator'` (tray toggle + status, config-driven values —
   the user's original setup, which also fixes multi-monitor since the
   daemon owns all outputs from login). ControlSlider/ToggleSwitch stay
   (AudioMenu volume slider + mute still use them).

### Phase 6 review pass (2026-08-14)

Read the pam conversation source (0.3.0) and re-audited every assumption:

- **abort() emits nothing** — Esc (Pam.cancel) SIGKILLs the subprocess and
  fires no completed/error signal, so no spurious failure text; the next
  tryUnlock starts a fresh conversation (onCompleted/onError both call
  abortConversation → conversation=null → start() works).
- **Errors fire BOTH error and completed(Error)** — the onError handler was
  dead code (completed(Error) overwrote its message, and the order is
  error-then-completed). Dropped onError; onCompleted handles Error →
  "Authentication error" explicitly.
- **Pam.qml simplified**: showFailure + pamMessage + unused active alias
  → single `failureText` ("" = no failure). pam_unix sends no meaningful
  messages, so the message plumbing was pure state.
- **Lock.qml: dropped the `wallpaperProbe` eager-instantiation hack** —
  lazy singleton creation at first lock is fine (the probe is ~1 frame
  behind a dark0 base, invisible). Simpler.
- **Lock.qml: dropped the `swaymsg dpms on` spawn on unlock** — every real
  unlock involves typing → input → swayidle `resume` already runs `dpms
  on`; the IPC-unlock path is test-only. Redundant spawn gone.
- **LockSurface.qml**: native rendering dropped (antialiases poorly over a
  photo background — the official example's tip applies to solid-color
  locks); `cache: false` dropped (default image cache makes relocks
  instant); Column restructured (nested columns instead of a 28+44
  wrapper Item); unused ids removed.
- **Wallpaper.qml**: dropped the .png fallback candidate — this repo's
  sway config always paints wallpaper.jpg; swapping the file type would
  break sway's `bg` line anyway. Single sh-builtin probe remains (QML has
  no $HOME expansion or file-exists check; same probe pattern as
  Brightness's backlight scan). Missing file → url "" → Image fails →
  dark0 base.

Re-verified live: clean load, lock → secure → unlock cycle with 0 errors,
wallpaper probe resolves at first lock.

### Phase 5 review pass (2026-08-13)

- **Brightness: ad-hoc 500ms poll → native FileView watch.** The plan's
  audit claimed FileView was "HEAD-only" and unusable for brightness —
  both wrong. Verified: FileView exists in installed 0.3.0-2, and
  inotify DOES deliver events on sysfs brightness files (raw inotify
  test on kernel 7.1.8 + a quickshell throwaway config watching
  `/sys/class/leds/.../brightness`: loaded + fileChanged fired).
  `Brightness.qml` now watches the backlight file with `FileView
  { watchChanges: true }` (event-driven, instant); a 2s safety poll
  remains as insurance for kernels where sysfs inotify is inert (a
  no-op re-read when the watch fires first). The initial reading comes
  from `onLoaded` (file-read completion — not inotify-dependent), so the
  first value is never delivered late. Spawn rate drops from 2/s to
  ~0.5/s; the bar widget and OSD react instantly on modern kernels.
- **Osd: deterministic startup window + source-level dedupe.** The armed
  window went 600ms → 1500ms so it always covers the initial readings
  (sink attach emit + brightness onLoaded — both land ~within 1s;
  safe on every kernel, no race). The volume echo dedupe moved out of
  `show()` into `onVolumeChanged` (lastVol/lastMutedShown): a
  quickshell-side write emits the Pipewire signal locally AND on the
  server echo — only the first identical pair shows. `show()` is now
  a dumb set-state-and-log (the source dedupes); the armed flag
  replaced the per-source seen-flags (which had a first-change hole
  when the initial value was already current at instantiation).
- **Deliberately kept:** `focusedScreen()` is duplicated between
  Osd.qml and Notifications.qml — a shared module for one 10-line
  function isn't worth the churn on verified phase-4 code (noted in
  both files).

### Review pass (2026-08-13)

- Dropped the unused `newNotification` signal and the redundant `popup`
  flag on wrappers (popup membership IS the `popups` array).
- Popup timeouts are now event-driven: one one-shot timer armed to the
  soonest popup deadline (re-arms after each popup-state change). No
  periodic wakeups — a persistent critical/resident popup (timeout 0)
  never arms the timer at all, and hover-pause just removes a popup from
  the schedule (remaining stored, deadline rebuilt on resume). Replaced
  the 250ms polling ticker.
- `transient` read from the native Notification property instead of the
  `hints` map; `timeoutFor` now honors the native `resident` property
  (resident notifications never auto-dismiss their popup).
- Enabling DND ends any popups still on screen (swaync behavior).
- Icon resolution uses the native `Quickshell.iconPath()` for theme names
  (kept the absolute-path → `file://` branch; quickshell has no
  client-side notify API and libnotify is absent, so `test()` stays on
  gdbus).
- Action buttons capped at 140px wide; stale comments fixed; center
  height properties moved to the top.
- Re-verified live: full sweep clean (0 errors), DND suppress+store,
  clear, timeouts; user-confirmed hover-pause with the new driver.

### Phase 1-5 efficiency & portability pass (2026-08-13)

Implemented the playbook fixes (each self-contained, hot-reload-safe):

- **CpuMemTemp: single-`cat` pipeline.** The poll command is now
  `cat /proc/stat /proc/meminfo /sys/class/hwmon/hwmon*/temp*_input`
  (2 forks/tick instead of ~10: the old sh+grep+awk+N×cat+sort+tail).
  Parser updated: meminfo lines are filtered to MemTotal/MemAvailable
  (first number per line) and the hottest temp is `Math.max(...temps)/1000`
  — same semantics as the old sort|tail -1.
- **Brightness: fully native reads.** FileView (inotify, verified) watches
  the device's `brightness` file; `percent = raw / max_brightness` from the
  file contents. Pattern: `preload: true` (initial), `onFileChanged:
  reload()`, read `text()` in `onInternalTextChanged`/`onLoaded` — the
  watcher does NOT refresh the buffer itself (verified with a throwaway
  config: preload:true returned stale, preload:false returned empty). The
  2s `brightnessctl -m get` safety poll is gone (0.5 spawn/s forever for an
  unverified failure mode). `brightnessctl` remains only for *writes*
  (bar widget). Bonus: the shell now works on machines without
  brightnessctl installed. Untestable here (no backlight on this machine) —
  needs verification on a machine with one.
- **NetworkWidget.findActive fixed.** The old `i === 0 ? networks :
  d.networks.values` index hack never scanned the ethernet device's own
  networks when a wifi device existed → wired-only connections showed as
  disconnected. Now: connected wifi first, then every device's own
  networks. (Logic unit-tested in node; live wifi path unchanged.)
- **MprisWidget.focusPlayerWindow: native.** Dropped the pgrep+swaymsg
  shell spawn; now raises via MPRIS and activates the matching
  `ToplevelManager` toplevel (appId vs desktopEntry, exact then
  substring). No subprocess, works without swaymsg in PATH.
- **TrayWidget**: dropped the inert `Layout.preferredHeight` (parent is a
  plain Column — `height` is the sizing property) + removed the unused
  QtQuick.Layouts import.
- **ClockWidget**: uses SystemClock's native `hours`/`minutes` (zero-
  padded) instead of `Qt.formatDateTime`.
- **Comments**: corrected the "bare function call evaluates once" framing
  in Workspaces/Launcher/NotificationCenter/PolkitDialog — the guard is
  needed because `I3.monitorFor` is a native C++ method, not because
  function calls aren't tracked.
- **install.md**: documented quickshell 0.3.0 (pin) + runtime deps
  (pipewire, brightnessctl, polkit, networkmanager, upower, wl-clipboard,
  grim) and the sway ≥ 1.8 requirement.

Verified: node unit tests for the CpuMemTemp parser and findActive logic;
FileView text() blocking-read pattern verified with a throwaway config on a
plain file (see the playbook); live shell reloaded clean (0 errors, log
checked after the final save).

## Landmine audit (2026-08-13)

The user challenged landmine 5 ("PopupWindow is broken on wlr-layer-shell").
Verified empirically with throwaway configs (`quickshell -p /tmp/qstestN`,
separate instances, live sway 1.12) — the plan entries above were corrected
in place:

- **xdg_popup attach to a layer surface works.** Test A: PopupWindow
  anchored to a PanelWindow, `visible` from startup, no grab → clean attach
  (only deprecation warnings). Test B: `grabFocus: true` → Qt fails first
  ("Failed to create grabbing popup… parent window has received input"),
  then quickshell's fallback warns "the popup is not an xdg_popup" and the
  popup does not attach. Test C: popup created hidden with grabFocus, shown
  later, still no input → same failure. Test D: hidden, shown later, no
  grab → clean.
- **Root cause is xdg-shell grab semantics, not a layer-shell bug**: a
  grabbing xdg_popup needs an input serial from the parent window. Real
  clicks (the opening click on a bar widget) provide it. Confirmed
  indirectly: the live shell's qslog has zero xdg_popup warnings while the
  click-opened popups demonstrably render.
- **Two other plan entries described code that no longer exists**: the
  taskbar uses the native ToplevelManager (not get_tree parsing), and
  AnchoredPopup is a PopupWindow (not the old LayerPopup/PopupBackdrop).
  Corrected entries 3, 5, 6, 7 accordingly.

### Assumption audit — all phases (2026-08-13)

Every tagged assumption was re-verified with throwaway configs on live
sway 1.12 (separate `quickshell -p` instances, logs + `swaymsg` focus
signals):

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| P2-1 | ObjectModel has `.values`, not `.length` | **true** | qmltypes: `values` (notify `valuesChanged`), no length/count |
| P2-2 | Function calls in bindings never tracked | **false** | bare QML function reads tracked (n=1..6 re-eval); only native method internals aren't — the `I3.monitorFor` guard is still needed |
| P2-8 | Inline components can't see root props | **false** | inline comp read `root.n` fine (PowerMenu already did) |
| P3-9 | Delegates get no `index` | **root-caused** | `required property var modelData` kills `index`; implicit `modelData` + `index` works. Launcher refactored to native index/isCurrentItem |
| P1-q2 | Structural hot reload fails to map | **false in isolation** | added a PanelWindow via file edit → mapped + grabbed, 0 errors. But a live-session reload left grab state stale once — restart after significant edits is still prudent |
| P1 | MultiEffect avoids qt5compat | moot | MultiEffect unused; qt6-5compat/imageformats not installed, not needed |
| P1 | sway ≥1.8 (ext-session-lock) | **true** | sway 1.12 |

No other phase-2/3 assumptions were found questionable (popup anchoring,
DesktopEntries async scan, `.values` reactivity, polling services with no
native alternative — see the phase-5 audit below, which corrected the
"FileView is HEAD-only" claim: FileView IS present in the installed
0.3.0-2 and its QFileSystemWatcher backend does deliver events on sysfs
(verified with raw inotify AND a quickshell throwaway config).

**Pattern:** of the assumptions that were actually verified, most were
false or misdiagnosed. All were tagged by agents without a minimal
reproduction. Future agents: reproduce first, tag later (see Agent
working rules at the top of this plan).
