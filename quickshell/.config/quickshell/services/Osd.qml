// services/Osd.qml — on-screen display state for volume / brightness.
//
// A pure observer: it never changes anything — it shows a brief overlay
// whenever the *system* volume or brightness changes, from any source
// (bar widgets, sway keybindings via wpctl / brightnessctl, apps). The
// overlay itself lives in popups/OsdPopup.qml (one window per screen,
// routed by `screen`).
//
// Volume is event-driven via Pipewire (instant). Brightness is event-
// driven via the Brightness service's FileView watch (inotify on sysfs).
// Both land inside a short startup window (armed) that suppresses the
// sink's initial-params emit and the brightness service's first reading —
// no OSD pops up on load or hot reload. The volume dedupe also absorbs
// Pipewire's local+echo double emit (a quickshell write signals twice).
pragma Singleton

import Quickshell
import Quickshell.I3
import Quickshell.Services.Pipewire
import QtQuick
import qs.services

Singleton {
    id: root

    /// What is shown: "volume" | "brightness" | "" (hidden).
    property string kind: ""
    /// Level in percent (0..100).
    property int level: 0
    /// Muted (only meaningful for kind === "volume").
    property bool muted: false
    /// Screen to show on (the monitor focused when the change happened).
    property var screen: null

    readonly property bool active: root.kind !== ""

    // ── Volume: event-driven via Pipewire ──────────────────────────────
    // Keep the default sink alive while watching it (official example
    // pattern: without a tracker the node may be released).
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    Connections {
        // `audio` is constant for a given node, so the target re-attaches
        // only when the default sink itself changes. Explicit null (not
        // `?.` — that yields undefined and trips a QObject* assign warn).
        target: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null

        function onVolumesChanged() { root.onVolumeChanged(); }
        function onMutedChanged() { root.onVolumeChanged(); }
    }

    // Last shown volume/mute: a repeated identical pair is the server
    // echo of a quickshell-side write — re-arm the timer, don't re-show.
    property int lastVol: -1
    property bool lastMutedShown: false

    function onVolumeChanged(): void {
        if (!root.armed) return; // sink attach emit / startup noise
        const node = Pipewire.defaultAudioSink;
        if (!node || !node.audio) return;
        const pct = Math.max(0, Math.min(100, Math.round(node.audio.volume * 100)));
        const muted = node.audio.muted;
        if (pct === root.lastVol && muted === root.lastMutedShown) return;
        root.lastVol = pct;
        root.lastMutedShown = muted;
        root.show("volume", pct, muted);
    }

    // ── Brightness: event-driven via the Brightness service (FileView) ─
    // percent only changes on real changes (the safety poll re-reads the
    // same value), so a plain armed gate suffices — no dedupe needed.
    property int lastBright: Brightness.percent
    onLastBrightChanged: {
        if (root.armed && root.lastBright >= 0)
            root.show("brightness", root.lastBright, false);
    }

    // ── Show / hide ────────────────────────────────────────────────────
    Timer {
        id: hideTimer
        interval: 1000
        onTriggered: root.kind = ""
    }

    /// Show the OSD for ~1s (extended by every subsequent change).
    function show(kind: string, level: int, muted: bool): void {
        root.kind = kind;
        root.level = level;
        root.muted = muted;
        root.screen = root.focusedScreen();
        hideTimer.restart();
        console.log("[osd] " + kind + " " + level + (muted ? " muted" : ""));
    }

    /// Screen for the OSD: the monitor focused at trigger time (by name),
    /// falling back to the first screen. (Same helper as in
    /// services/Notifications.qml — a shared module for one 10-line
    /// function isn't worth it; kept in sync deliberately.)
    function focusedScreen(): var {
        const mon = I3.focusedMonitor;
        const screens = Quickshell.screens;
        if (mon) {
            for (let i = 0; i < screens.length; i++) {
                if (screens[i].name === mon.name) return screens[i];
            }
        }
        return screens.length ? screens[0] : null;
    }

    // ── Startup window ─────────────────────────────────────────────────
    // The sink's initial-params emit and the brightness first reading both
    // land within ~1s of shell start; ignore everything until then. (No
    // real change is lost in practice — the user isn't changing volume
    // within the first 1.5s of a shell load.)
    property bool armed: false
    Timer {
        interval: 1500
        running: true
        onTriggered: root.armed = true
    }
}
