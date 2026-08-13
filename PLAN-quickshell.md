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

### Review pass (2026-08-13)

- Dropped the unused `newNotification` signal and the redundant `popup`
  flag on wrappers (popup membership IS the `popups` array).
- Ticker now runs only while popups exist (`running: popups.length > 0`).
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
  clear, timeouts.

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
native alternative — `Quickshell.Io` has no file-watch type in 0.3.0;
FileView is HEAD-only).

**Pattern:** of the assumptions that were actually verified, most were
false or misdiagnosed. All were tagged by agents without a minimal
reproduction. Future agents: reproduce first, tag later (see Agent
working rules at the top of this plan).
