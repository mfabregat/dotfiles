# Plan: Port sway desktop environment to Quickshell

Status: **approved blueprint** — implementation follows the phases below.
Date: 2026-08 · Quickshell 0.3.0 (Arch `extra/quickshell`, latest release, docs at `quickshell.org/docs/v0.3.0`)

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
    LockSurface.qml      # per-screen surface, screencopy blur, keyboard grab
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
- **Blur trick**: warm up a ScreencopyView before locking (first capture
  fails if it's the first request) — caelestia workaround.

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
6. **Lock screen + swayidle** — PAM, blur, IPC, dpms; `$mod+P`.
7. **Extras** — control center, clipboard, network menu, night light,
   screenshot picker. Replace grimshot keybind.
8. **Cleanup** — drop waybar/waybar_top/swaylock/rofi stow packages, prune
   autostart, update README + install.md, document quickshell version pin.

## Risks & notes

- Quickshell is pre-1.0: breaking changes on upgrades — pin `0.3.0` in
  install.md, configs in git.
- Screencopy blur can be flaky on NVIDIA (this machine runs sway with
  `--unsupported-gpu`); fallback: solid dark background behind lock.
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
- **Quirk 2 — reload flakiness**: structural changes to the scene root
  across hot reloads sometimes fail to map windows (0.3.0 behavior);
  property-level changes reload fine. Workflow: restart quickshell after
  structural edits (`pkill -x quickshell`), hot-reload for styling.
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
2. **Function calls in QML bindings are never tracked** — `property var x:
   lookup()` evaluates once. Fix: pass a tracked property as an argument
   (`lookup(SomeModel.values)`).
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
8. Inline components can't see property aliases or root props — use
   `parent.width` or plain properties.

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
- **New landmine 9 — delegates get no `index`** (neither ListView nor
  Repeater, quickshell 0.3.0 + Qt 6.11): `ReferenceError: index is not
  defined`. Every existing widget only ever uses `modelData` — selection is
  tracked by object identity (`entry === root.selectedEntry`). The results
  list is a Repeater + Column over a `visibleResults` slice (scrollOffset
  window), scrolling via a 8-row window with Up/Down.
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
