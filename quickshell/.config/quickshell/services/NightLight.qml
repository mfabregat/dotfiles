// services/NightLight.qml — gammastep wrapper (blue-light filter).
// Replaces the old gammastep-indicator tray app (its sway autostart line
// is gone); the control center hosts the toggle + sliders.
//
// Apply model (verified against the installed gammastep 2.0.11, -p print
// mode): enabled → `gammastep -O <K> -P -b <day>:<night>` — one-shot, the
// process applies the gamma ramps and exits (no daemon), -O keeps the
// temperature constant and -b picks the day/night brightness by the
// current solar elevation. disabled → `gammastep -x` (reset ramps).
//
// State persists to ~/.local/state/quickshell-nightlight (JSON) so the
// filter survives logins: written on every change (user-driven, no
// tickers), read once at startup, then applied.
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
    /// One-shot color temperature in Kelvin.
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

    // ── Apply ──────────────────────────────────────────────────────────
    // Slider drags re-apply through a short debounce (gammastep is a
    // few-hundred-ms spawn each time).
    Timer {
        id: applyDebounce
        interval: 150
        repeat: false
        onTriggered: root.apply()
    }

    Timer {
        id: saveDebounce
        interval: 300
        repeat: false
        onTriggered: root.saveState()
    }

    function apply(): void {
        if (!root.available) return;
        if (root.enabled) {
            Quickshell.execDetached([
                "gammastep", "-O", String(root.temperature), "-P",
                "-b", root.dayBrightness.toFixed(2) + ":" + root.nightBrightness.toFixed(2)
            ]);
        } else {
            // Also resets any leftover filter from the old gammastep
            // daemon / a previous session.
            Quickshell.execDetached(["gammastep", "-x"]);
        }
    }

    function maybeApply(): void {
        if (root.available && root.stateLoaded) root.apply();
    }

    // ── Setters (state + debounced apply/save) ─────────────────────────
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
        if (root.enabled) applyDebounce.restart();
    }

    function setDayBrightness(v: real): void {
        const b = clampB(v);
        if (b === root.dayBrightness) return;
        root.dayBrightness = b;
        saveDebounce.restart();
        if (root.enabled) applyDebounce.restart();
    }

    function setNightBrightness(v: real): void {
        const b = clampB(v);
        if (b === root.nightBrightness) return;
        root.nightBrightness = b;
        saveDebounce.restart();
        if (root.enabled) applyDebounce.restart();
    }

    function clampTemp(k: int): int {
        if (isNaN(k)) return root.temperature;
        return Math.max(root.minTemp, Math.min(root.maxTemp, Math.round(k)));
    }

    function clampB(v: real): real {
        if (isNaN(v)) return 1.0;
        return Math.max(0.1, Math.min(1.0, Math.round(v * 100) / 100));
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
