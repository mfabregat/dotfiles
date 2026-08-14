// services/Clipboard.qml — clipboard history ring + IPC entry point.
//
// Watching: `wl-paste --watch` (wl-clipboard). Quickshell's native
// Quickshell.clipboardText was verified with throwaway configs
// (2026-08-14) to only notify on *self-writes* — external copies never
// fire clipboardTextChanged and external offers read back empty — so the
// plan's wl-paste watch is the only reliable source. wl-paste --watch
// spawns the given command with each new clipboard text on stdin; the
// command echoes it plus an ASCII RS byte (0x1E) and SplitParser splits on
// RS, so one clipboard change == exactly one chunk even for multi-line
// content (verified with a stub against the installed 0.3.0-2).
//
// Availability: probed once (`command -v wl-paste && command -v wl-copy`).
// Without wl-clipboard the ring stays inert instead of erroring —
// `sudo pacman -S wl-clipboard` enables it (install.md).
pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    /// wl-clipboard present (both tools are needed: watch + copy).
    property bool available: false
    /// Ring buffer, newest first, capped at root.maxItems. Plain strings;
    /// mutations always reassign the array so bindings re-evaluate
    /// (landmine 2 pattern).
    property var items: []
    /// Clipboard popup open state (IPC + UI).
    property bool open: false

    readonly property int maxItems: 20

    // ── Availability probe (one-time; sh builtin — no periodic spawns) ─
    Process {
        id: probe
        command: ["sh", "-c", "command -v wl-paste && command -v wl-copy"]
        running: false
        onExited: exitCode => {
            root.available = exitCode === 0;
            console.log("[clipboard] available: " + root.available);
        }
    }

    // ── Watcher (long-running, event-driven) ───────────────────────────
    // `cat; printf '\036'` echoes the content and terminates it with RS;
    // SplitParser strips the marker, so onRead delivers one clean chunk
    // per clipboard change. NOTE: no `--` before the command — getopt
    // consumes it as `--watch`'s argument and rejects it ("Expected a
    // subcommand instead of an argument after --watch" — verified
    // 2026-08-14 against wl-clipboard 2.3.0). If wl-paste dies the
    // watcher stops until the shell reloads — it never exits on its own
    // in practice.
    Process {
        id: watcher
        command: ["wl-paste", "--type", "text/plain", "--watch",
                  "sh", "-c", "cat; printf '\\036'"]
        running: root.available
        stdout: SplitParser {
            splitMarker: "\u001e"
            onRead: data => root.onClipChanged(data)
        }
    }

    function onClipChanged(text: string): void {
        if (text.length === 0) return; // cleared clipboard
        // Dedupe: our own wl-copy echoes back through the watch, and a
        // repeated copy shouldn't stack. Duplicates move to the head.
        if (root.items.length > 0 && root.items[0] === text) return;
        let next = [text].concat(root.items.filter(x => x !== text));
        if (next.length > root.maxItems) next.length = root.maxItems;
        root.items = next;
        console.log("[clipboard] captured: " + text.slice(0, 40));
    }

    // ── Actions ────────────────────────────────────────────────────────
    /// Copy `text` to the clipboard. Argument-based wl-copy (no shell, no
    /// injection risk). The watcher will echo it back; the head-dedupe
    /// makes that a no-op.
    function copy(text: string): void {
        Quickshell.execDetached(["wl-copy", "--type", "text/plain", "--", text]);
    }

    function removeAt(i: int): void {
        root.items = root.items.filter((_, idx) => idx !== i);
    }

    function clear(): void {
        root.items = [];
    }

    function toggle(): void { root.open = !root.open; }

    IpcHandler {
        target: "clipboard"

        function toggle(): void { root.toggle(); }
        function clear(): void { root.clear(); }
        function count(): int { return root.items.length; }
    }

    Component.onCompleted: probe.running = true
}
