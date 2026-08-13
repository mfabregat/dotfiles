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
