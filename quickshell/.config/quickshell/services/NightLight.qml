// services/NightLight.qml — gammastep wrapper (blue-light filter).
//
// Architecture (2026-08-14 redesign — verified against gammastep 2.0.11
// source + live behavior):
// - gammastep runs as ONE long-lived daemon. `-O` and `-x` modes do NOT
//   exit ("Press ctrl-c to stop...") — they stay connected to the
//   compositor, and wlr-gamma-control allows exactly ONE owner per
//   output. Every extra process fails with "Zero outputs support gamma
//   adjustment" but hangs anyway — the old code accumulated ~30 of them
//   and nothing visibly changed. Never spawn more than one: change
//   values by restarting it (kill + exec, ~50ms neutral flash), toggle
//   off by killing it (sway reverts the gamma LUT when the client
//   disconnects).
// - gammastep has NO config file watching and no SIGHUP reload — the
//   config is read once at startup; SIGUSR1 only toggles disable
//   (signals.c / redshift.c, verified in source). Value changes therefore
//   go through a daemon restart, not a config edit.
// - The daemon is spawned detached (survives quickshell restarts); sway
//   does NOT run gammastep — one owner only.
// - Cosmetic quirk: gammastep NUL-splits the -b/-t argv strings in place
//   while parsing DAY:NIGHT, so `ps` shows `-b 0.42 0.63` — the colon
//   became a NUL; the values were always parsed correctly.
//
// Apply model: enabled → `gammastep -O <K> -P -g 1.0 -b <d>:<n>` —
// constant temperature (the single slider), -b picks the day/night
// brightness by solar elevation, -g 1.0 neutralizes the user config's
// gamma so the brightness sliders own dimming, location + adjustment
// method come from the user's gammastep config. disabled → kill the
// daemon (gamma reverts to neutral, no process left).
//
// State persists to ~/.local/state/quickshell-nightlight (JSON): written
// on change (debounced), read + applied once at startup. Slider changes
// do NOT auto-apply — the popup calls apply() on slider release so a
// drag doesn't restart the daemon every tick.
pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    /// gammastep installed (probed once at startup).
    property bool available: false
    /// Filter active.
    property bool enabled: false
    /// Constant color temperature in Kelvin.
    property int temperature: 4000
    /// gammastep -b DAY:NIGHT values (screen brightness 0.1–1.0).
    property real dayBrightness: 1.0
    property real nightBrightness: 0.7

    readonly property int minTemp: 1000
    readonly property int maxTemp: 6500
    /// State file. Fixed path (Quickshell.stateDir is per-shell-instance
    /// and would not survive restarts); built from $HOME via Quickshell.env
    /// (verified 2026-08-14 — QML can't expand $HOME itself).
    readonly property string statePath: (Quickshell.env("HOME") || "")
        + "/.local/state/quickshell-nightlight"

    property bool stateLoaded: false

    // ── Availability probe (one-time; sh builtin, like Brightness/Wallpaper)
    Process {
        id: probe
        command: ["sh", "-c", "command -v gammastep"]
        running: false
        onExited: exitCode => {
            root.available = exitCode === 0;
            console.log("[nightlight] available: " + root.available);
            root.maybeApply();
        }
    }

    // ── State read (once at startup; FileView is fully native) ─────────
    FileView {
        id: state
        path: root.statePath
        preload: true
        onLoaded: root.loadState()
    }

    function loadState(): void {
        const raw = String(state.text()).trim();
        if (raw.length > 0) {
            try {
                const s = JSON.parse(raw);
                root.enabled = !!s.enabled;
                root.temperature = clampTemp(parseInt(s.temperature, 10));
                root.dayBrightness = clampB(parseFloat(s.day));
                root.nightBrightness = clampB(parseFloat(s.night));
            } catch (e) {
                console.log("[nightlight] state parse error: " + e);
            }
        }
        root.stateLoaded = true;
        root.maybeApply();
    }

    // ── Apply: one daemon, restarted on change ─────────────────────────
    /// Bring the daemon in line with the current state. Enabled: kill any
    /// leftover and spawn one with the current values (the sh exec
    /// replaces the shell, so exactly one detached gammastep remains).
    /// Disabled: kill the daemon — the gamma LUT reverts to neutral.
    function apply(): void {
        if (!root.available) return;
        if (root.enabled) {
            Quickshell.execDetached([
                "sh", "-c",
                'pkill -x gammastep 2>/dev/null; exec gammastep -O "$1" -P -g 1.0 -b "$2"',
                "--", String(root.temperature),
                root.dayBrightness.toFixed(2) + ":" + root.nightBrightness.toFixed(2)
            ]);
        } else {
            Quickshell.execDetached(["sh", "-c", "pkill -x gammastep 2>/dev/null"]);
        }
    }

    function maybeApply(): void {
        if (root.available && root.stateLoaded) root.apply();
    }

    // ── Setters ────────────────────────────────────────────────────────
    // Setters update state + persist (debounced) but never restart the
    // daemon themselves — the popup calls apply() on slider release and
    // setEnabled applies immediately (a toggle must feel instant).
    function setEnabled(v: bool): void {
        if (root.enabled === v) return;
        root.enabled = v;
        saveDebounce.restart();
        root.apply();
    }

    function setTemperature(k: int): void {
        const t = clampTemp(k);
        if (t === root.temperature) return;
        root.temperature = t;
        saveDebounce.restart();
    }

    function setDayBrightness(v: real): void {
        const b = clampB(v);
        if (b === root.dayBrightness) return;
        root.dayBrightness = b;
        saveDebounce.restart();
    }

    function setNightBrightness(v: real): void {
        const b = clampB(v);
        if (b === root.nightBrightness) return;
        root.nightBrightness = b;
        saveDebounce.restart();
    }

    function clampTemp(k: int): int {
        if (isNaN(k)) return root.temperature;
        return Math.max(root.minTemp, Math.min(root.maxTemp, Math.round(k)));
    }

    function clampB(v: real): real {
        if (isNaN(v)) return 1.0;
        return Math.max(0.1, Math.min(1.0, Math.round(v * 100) / 100));
    }

    Timer {
        id: saveDebounce
        interval: 300
        repeat: false
        onTriggered: root.saveState()
    }

    /// Persist state to the state file (one rare spawn, user-driven).
    function saveState(): void {
        const json = JSON.stringify({
            enabled: root.enabled,
            temperature: root.temperature,
            day: root.dayBrightness,
            night: root.nightBrightness
        });
        Quickshell.execDetached([
            "sh", "-c",
            'mkdir -p "$(dirname "$2")"; printf %s "$1" > "$2"',
            "--", json, root.statePath
        ]);
    }

    IpcHandler {
        target: "nightlight"

        function toggle(): void { root.setEnabled(!root.enabled); }
        function on(): void { root.setEnabled(true); }
        function off(): void { root.setEnabled(false); }
    }

    Component.onCompleted: probe.running = true
}
