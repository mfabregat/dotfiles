// services/Screenshot.qml — screenshot state + capture (grim backend).
// The picker overlay (popups/ScreenshotPicker.qml) drives `open`; capture
// is spawned here. grim is used for capture (the plan deliberately avoids
// ScreencopyView). grim's -g geometry is in the global output layout —
// verified 2026-08-14: `grim -g "1920,0 1920x1080"` is byte-identical to
// `grim -o DP-1` with DP-1 at x=1920, matching Quickshell.screen.x/y.
//
// Capture ordering (verified the same day): grim composites layer-shell
// surfaces, so the picker windows MUST be hidden before the capture runs
// or the selection overlay would appear in the shot. capture() sets
// `open = false` first; on failure it re-opens the picker.
//
// Result: PNG saved to ~/Pictures/Screenshots/qs-<timestamp>.png and
// copied to the clipboard when wl-copy is installed (silently skipped
// otherwise); a notification (our own daemon, via gdbus) reports the path.
pragma Singleton

import Quickshell
import Quickshell.I3
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    /// Picker overlay open (ScreenshotPicker windows bind visibility).
    property bool open: false

    // ── Capture ────────────────────────────────────────────────────────
    Process {
        id: capProc
        command: []
        stdout: StdioCollector {
            onStreamFinished: root.onCaptured(this.text.trim())
        }
        onExited: exitCode => {
            // A previous capture terminated by a newer one also exits
            // non-zero (within ~50ms of the new spawn) — don't re-open
            // the picker for that. Only a failure of a standalone capture
            // (no newer one within half a second) brings the picker back.
            if (exitCode !== 0 && Date.now() - root.lastCaptureAt > 500) {
                root.open = true;
                console.log("[screenshot] capture failed (exit " + exitCode + ")");
            }
        }
    }

    /// Timestamp of the most recent capture() (for the guard above).
    property int lastCaptureAt: 0

    /// Capture the given output-layout geometry ("x,y wxh", global coords)
    /// and save it. Hides the picker first (see header comment).
    function capture(geometry: string): void {
        root.open = false;
        root.lastCaptureAt = Date.now();
        capProc.command = [
            "sh", "-c",
            'd="$HOME/Pictures/Screenshots"; mkdir -p "$d"; '
            + 'f="$d/qs-$(date +%Y%m%d-%H%M%S-%N).png"; '
            + 'grim -g "$1" - > "$f" '
            + '&& { command -v wl-copy >/dev/null 2>&1 && wl-copy --type image/png < "$f"; } '
            + '&& echo "$f"',
            "--", geometry
        ];
        capProc.running = false;
        capProc.running = true;
    }

    /// Area capture from the picker (window-local coords + its screen).
    function captureRect(x: int, y: int, w: int, h: int, screen: var): void {
        if (!screen) return;
        const gx = Math.round(screen.x + x);
        const gy = Math.round(screen.y + y);
        const gw = Math.max(1, Math.round(w));
        const gh = Math.max(1, Math.round(h));
        root.capture(gx + "," + gy + " " + gw + "x" + gh);
    }

    /// Fullscreen capture of the focused monitor (Shift+Print; no UI).
    function captureFull(): void {
        const scr = root.focusedScreen();
        if (!scr) return;
        root.capture(Math.round(scr.x) + "," + Math.round(scr.y) + " "
            + Math.round(scr.width) + "x" + Math.round(scr.height));
    }

    // ── Window pick (ctrl+click in the picker) ──────────────────────────
    // The native ToplevelManager exposes NO window geometry (only
    // appId/title/activated/screens — verified in the qmltypes), and the
    // I3 module has no node trees, so a single `swaymsg -t get_tree` parse
    // per user click is the established way (grimshot does the same).
    // Event-driven (human-scale, well under the spawn budget) — not the
    // taskbar pattern the plan's no-get_tree rule targets.
    Process {
        id: treeProc
        command: ["swaymsg", "-t", "get_tree"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.onTree(this.text)
        }
    }

    property int pickX: 0
    property int pickY: 0

    /// Ctrl+click in the picker: capture the window under the cursor
    /// (cursor in output-layout coords). The picker stays up during the
    /// lookup; capture() hides it before grim runs.
    function captureWindowAt(gx: int, gy: int): void {
        root.pickX = gx;
        root.pickY = gy;
        treeProc.running = false;
        treeProc.running = true;
    }

    function onTree(text: string): void {
        let tree = null;
        try {
            tree = JSON.parse(text);
        } catch (e) {
            console.log("[screenshot] get_tree parse failed: " + e);
            return;
        }
        const rect = root.findWindowRect(tree, root.pickX, root.pickY);
        if (!rect) {
            console.log("[screenshot] no window under cursor");
            return;
        }
        root.capture(Math.round(rect.x) + "," + Math.round(rect.y) + " "
            + Math.round(rect.width) + "x" + Math.round(rect.height));
    }

    /// Walk the sway tree and return the rect of the visible window
    /// containing (x, y). Floating windows are drawn above tiled ones in
    /// sway; within a class the last one walked (most recent in the tree)
    /// wins. (Logic mirrored in a node unit test.)
    function findWindowRect(node: var, x: int, y: int): var {
        let best = null;
        let order = 0;
        const walk = (n, floating) => {
            if (n.type === "con" && n.app_id && n.visible) {
                const r = n.rect;
                if (r && x >= r.x && x < r.x + r.width && y >= r.y && y < r.y + r.height) {
                    const cand = { rect: r, floating: floating, order: order++ };
                    if (!best
                        || cand.floating > best.floating
                        || (cand.floating === best.floating && cand.order > best.order)) {
                        best = cand;
                    }
                }
            }
            for (const c of (n.nodes || [])) walk(c, floating);
            for (const c of (n.floating_nodes || [])) walk(c, true);
        };
        walk(node, false);
        return best ? best.rect : null;
    }

    /// Screen whose monitor is focused (by name), falling back to the
    /// first screen. I3.focusedMonitor is a notify property — no guard
    /// needed (playbook).
    function focusedScreen(): var {
        const mon = I3.focusedMonitor;
        const screens = Quickshell.screens;
        if (mon) {
            for (const s of screens) {
                if (s.name === mon.name) return s;
            }
        }
        return screens.length ? screens[0] : null;
    }

    function onCaptured(path: string): void {
        if (path.length === 0) return;
        console.log("[screenshot] saved " + path);
        root.notify(path);
    }

    /// Notify through our own daemon (gdbus — no client-side notify API
    /// in 0.3.0; same pattern as Notifications.sendTest). The image-path
    /// hint gives the popup a preview thumbnail.
    function notify(path: string): void {
        Quickshell.execDetached([
            "gdbus", "call", "--session",
            "--dest", "org.freedesktop.Notifications",
            "--object-path", "/org/freedesktop/Notifications",
            "--method", "org.freedesktop.Notifications.Notify",
            "qs-screenshot", "0", "camera-photo", "Screenshot taken",
            "Saved to " + path, "[]",
            "{'image-path': <'" + path + "'>}", "5000"
        ]);
    }

    IpcHandler {
        target: "screenshot"

        function pick(): void { root.open = true; }
        function full(): void { root.captureFull(); }
        function toggle(): void { root.open = !root.open; }
    }
}
