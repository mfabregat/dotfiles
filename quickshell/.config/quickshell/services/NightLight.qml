// services/NightLight.qml — native gammastep integration (replaces the
// gammastep-indicator tray app; no Python/GTK/tray involved).
//
// Architecture (2026-08-15, verified against gammastep 2.0.11 source +
// live behavior on sway/wlroots):
// - gammastep runs as ONE long-lived daemon connected to the compositor.
//   wlr-gamma-control allows exactly one owner per output and sway
//   reverts the gamma LUT when the client disconnects — the daemon must
//   stay alive for the filter to persist. The shell OWNS it as a managed
//   Quickshell.Io.Process: quickshell kills the child when it exits (no
//   orphaned daemons on reload/restart) and this service auto-restarts
//   it on crash (the LUT would silently revert otherwise).
// - gammastep has NO control channel (no DBus, no config watching, no
//   SIGHUP; the config is read once at startup). SIGUSR1 toggles the
//   filter off/on; a config edit applies only after a daemon restart
//   (ipc `restart`). That is the whole interaction surface — this
//   service exposes toggle + suspend + restart, and shows the
//   temperatures from the user's config. (A slider UI was tried earlier
//   and removed: value changes would need daemon restarts that race
//   per-output ownership on multi-monitor.)
// - State is parsed from gammastep's own verbose output — the exact
//   protocol the gammastep-indicator tray app reads:
//       Notice: Status: Enabled|Disabled
//       Notice: Period: Daytime|Night|Transition|None
//       (during a transition the Period line carries the progress:
//        "Transition (Day: 45.57%)" — day-fraction of the
//        interpolation, 100% at dusk start → 0% at full night,
//        rising back to 100% at dawn finish)
//       Notice: Color temperature: 6500K
//       Notice: Temperatures: 6500K (Day), 2200K (Night)  (config info)
//       Notice: Brightness: 1.00:0.70        (day:night, config info)
//       Notice: Gamma (Day): 1.000, 1.000, 1.000      (config info)
//       Notice: Gamma (Night): 0.850, 0.700, 0.500    (config info)
//   The child runs with a C locale so the keys stay parseable regardless
//   of the user's locale (the indicator did the same).
pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    /// gammastep installed (probed once at startup).
    property bool available: false
    /// Filter active (parsed from gammastep's Status line).
    property bool enabled: true
    /// Current period: Daytime | Night | Transition | None (off).
    property string period: "Unknown"
    /// Transition position as a day-fraction 0-100: how far the screen
    /// is from NIGHT toward DAY colors (the "Day: xx%" the daemon
    /// appends to the Period line while transitioning). Meaningful only
    /// when period === "Transition".
    property real transitionDay: 0
    /// Current target temperature in Kelvin (reported by the daemon).
    property int temperature: 6500

    // Config values the daemon read at startup (info display only —
    // parsed from its Temperatures/Brightness/Gamma startup lines, which
    // is ground truth and refreshes on every restart). Gamma is a
    // formatted string ("1.00" when uniform, "r:g:b" otherwise); ""
    // until the daemon reports it.
    property int configDay: 6500
    property int configNight: 2200
    property real configDayBrightness: 1.0
    property real configNightBrightness: 1.0
    property string configDayGamma: ""
    property string configNightGamma: ""

    // Suspend state (SIGUSR1 off + timed SIGUSR1 on — like the indicator).
    property bool suspended: false
    /// Seconds until the suspend timer re-enables the filter.
    property int suspendRemaining: 0

    // SIGUSR1 on Linux. Process.signal() is kill(pid, sig) on our own
    // child — no pkill races with unrelated instances.
    readonly property int sigusr1: 10

    // ── Availability probe (one-time; sh builtin, like Brightness/Wallpaper)
    // Also sweeps stray gammastep instances (e.g. a leftover from the old
    // gammastep-indicator at login): wlr-gamma-control allows one owner
    // per output, so the shell must be the only spawner. Runs before the
    // first spawn; on config reload the old daemon is already killed by
    // the Process teardown, so this only ever hits true strays.
    Process {
        id: probe
        command: ["sh", "-c", "command -v gammastep >/dev/null && { pkill -x gammastep 2>/dev/null || true; }"]
        running: false
        onExited: exitCode => {
            root.available = exitCode === 0;
            if (root.available) root.startDaemon();
        }
    }

    // ── The daemon ────────────────────────────────────────────────────
    Process {
        id: daemon
        command: ["gammastep", "-v"]
        // C locale: gammastep localizes its log lines; the parser keys on
        // the English "Notice: ..." form.
        environment: { "LANG": "C", "LC_ALL": "C", "LC_MESSAGES": "C" }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => root.parseLine(String(line))
        }
        onRunningChanged: running => {
            if (running) root.lastStartMs = Date.now();
        }
        onExited: (exitCode, exitStatus) => {
            if (!root.available) return;
            // Requested restart (config edit): respawn immediately. A
            // crash restarts with backoff instead — an idle daemon means
            // the LUT reverts to neutral. The backoff resets when the
            // daemon had been stable (alive >60s) before dying.
            if (root.pendingRestart) {
                root.pendingRestart = false;
                root.startDaemon();
            } else {
                if (Date.now() - root.lastStartMs > 60000) root.restartDelay = 3000;
                restartTimer.restart();
            }
        }
    }

    property int restartDelay: 3000
    /// Timestamp of the last daemon start (backoff reset heuristic).
    property real lastStartMs: 0
    Timer {
        id: restartTimer
        interval: root.restartDelay
        repeat: false
        onTriggered: {
            if (!root.available || daemon.running) return;
            root.startDaemon();
            root.restartDelay = Math.min(30000, root.restartDelay * 2);
        }
    }

    function startDaemon(): void {
        if (root.available && !daemon.running) daemon.running = true;
    }

    /// Restart the daemon. gammastep reads config.ini ONCE at startup —
    /// no live reload — so editing temp-day/temp-night/brightness in the
    /// stowed config requires a restart to take effect. Sequential
    /// stop→start (SIGTERM, wait for exit, then spawn): never overlaps
    /// with the dying process, so no per-output ownership race.
    property bool pendingRestart: false

    function restartDaemon(): void {
        if (!root.available || root.pendingRestart) return;
        restartTimer.stop();
        if (!daemon.running) {
            root.startDaemon();
            return;
        }
        root.pendingRestart = true;
        daemon.running = false; // SIGTERM; onExited does the respawn
    }

    // ── Output parsing ────────────────────────────────────────────────
    function parseLine(line: string): void {
        // "Notice: Key: Value" — anything else (errors, "poll: ...") ignored.
        // Key may contain parentheses ("Gamma (Day)").
        const m = line.match(/^Notice: ([\w ()]+): (.+)$/);
        if (!m) return;
        const key = m[1];
        const value = m[2];

        if (key === "Status") {
            root.enabled = value === "Enabled";
        } else if (key === "Period") {
            // "Transition (Day: 45.57%)" — extract the base period and
            // the transition day-fraction; plain "Night"/"Daytime"
            // have no suffix.
            const t = value.match(/^(\w+) \(Day: ([\d.]+)%\)$/);
            if (t) {
                root.period = t[1];
                root.transitionDay = parseFloat(t[2]);
            } else {
                root.period = value;
                root.transitionDay = 0;
            }
        } else if (key === "Color temperature") {
            root.temperature = parseInt(value, 10) || root.temperature;
        } else if (key === "Temperatures") {
            // "6500K (Day), 2200K (Night)" — what the daemon read from
            // config.ini (re-printed after every restart).
            const t = value.match(/^(\d+)K \(Day\), (\d+)K \(Night\)$/);
            if (t) {
                root.configDay = parseInt(t[1], 10);
                root.configNight = parseInt(t[2], 10);
            }
        } else if (key === "Brightness") {
            // Startup "1.00:0.70" — day:night brightness from the config.
            const parts = value.split(":");
            if (parts.length === 2) {
                const d = parseFloat(parts[0]);
                const n = parseFloat(parts[1]);
                if (!isNaN(d)) root.configDayBrightness = d;
                if (!isNaN(n)) root.configNightBrightness = n;
            }
        } else if (key === "Gamma (Day)") {
            root.configDayGamma = root.fmtGamma(value);
        } else if (key === "Gamma (Night)") {
            root.configNightGamma = root.fmtGamma(value);
        }
    }

    /// "1.000, 1.000, 1.000" → "1.00" (uniform channels collapse to one)
    /// "0.850, 0.700, 0.500" → "0.85:0.70:0.50".
    function fmtGamma(v: string): string {
        if (v === "") return "";
        const ch = v.split(",").map(s => (parseFloat(s) || 0).toFixed(2));
        return ch.every(c => c === ch[0]) ? ch[0] : ch.join(":");
    }

    // ── Controls (SIGUSR1) ────────────────────────────────────────────
    /// Flip the filter. A manual toggle cancels a pending suspend (the
    /// indicator behaved the same way).
    function toggle(): void {
        root.cancelSuspend();
        daemon.signal(root.sigusr1);
    }

    function setEnabled(v: bool): void {
        if (root.enabled === v) return;
        root.toggle();
    }

    /// Disable for `minutes`, then re-enable (SIGUSR1 off, timed SIGUSR1 on).
    function suspend(minutes: int): void {
        if (!root.available) return;
        root.cancelSuspend();
        root.suspended = true;
        root.suspendRemaining = minutes * 60;
        if (root.enabled) daemon.signal(root.sigusr1); // off now
        suspendTick.start();
    }

    function resumeNow(): void {
        root.cancelSuspend();
        if (!root.enabled) daemon.signal(root.sigusr1); // back on
    }

    function cancelSuspend(): void {
        root.suspended = false;
        root.suspendRemaining = 0;
        suspendTick.stop();
    }

    // One timer does both jobs: counts the remaining seconds for the
    // popup and fires the re-enable when it reaches zero.
    Timer {
        id: suspendTick
        interval: 1000
        repeat: true
        onTriggered: {
            if (--root.suspendRemaining <= 0) root.resumeNow();
        }
    }

    // ── IPC (keybinds: `quickshell ipc call nightlight toggle`) ───────
    IpcHandler {
        target: "nightlight"

        function toggle(): void { root.toggle(); }
        function on(): void { root.setEnabled(true); }
        function off(): void { root.setEnabled(false); }
        function suspend(minutes: int): void { root.suspend(minutes); }
        function resume(): void { root.resumeNow(); }
        /// Restart the daemon (config edits apply only at startup — see
        /// restartDaemon).
        function restart(): void { root.restartDaemon(); }
        function status(): string {
            return JSON.stringify({
                available: root.available,
                enabled: root.enabled,
                period: root.period,
                transitionDay: root.transitionDay,
                temperature: root.temperature,
                suspended: root.suspended,
                suspendRemaining: root.suspendRemaining,
                configDay: root.configDay,
                configNight: root.configNight,
                configDayBrightness: root.configDayBrightness,
                configNightBrightness: root.configNightBrightness,
                configDayGamma: root.configDayGamma,
                configNightGamma: root.configNightGamma
            });
        }
    }

    Component.onCompleted: probe.running = true
}
