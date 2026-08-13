// services/Brightness.qml — backlight brightness (brightnessctl).
// percent is -1 when no backlight is available (widget hides itself).
//
// Phase 5: availability requires a real `backlight`-class device (probe of
// /sys/class/backlight directly). The old code trusted brightnessctl's
// default-device selection, which falls back to keyboard LEDs when no
// backlight exists — on this desktop that lit up a phantom 0% widget (and
// would have spammed the OSD). The probe scans /sys/class/backlight
// directly.
//
// Change detection: a native FileView watch (inotify) on the backlight's
// brightness file — event-driven and instant. This replaces the original
// 500ms poll; verified working on sysfs with kernel 7.1.8 (the plan's
// old note that FileView is "HEAD-only" / can't watch sysfs was wrong on
// both counts — see the audit). A 2s safety poll remains as insurance for
// kernels where sysfs inotify is inert: whenever the watch fires first it
// is a no-op re-read of the same value. The initial reading comes from
// FileView's onLoaded (file-read completion — not inotify-dependent), so
// it works on every kernel.
// brightnessctl has no change-watch mode (`-m monitor` is the `max`
// operation — verified 2026-08-13 against the binary and the source).
pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property int percent: -1
    readonly property bool available: percent >= 0

    /// Brightness file of the first real backlight device, "" when none.
    property string backlightPath: ""

    Process {
        id: probeProc

        command: ["sh", "-c", "for d in /sys/class/backlight/*; do [ -r \"$d/brightness\" ] && echo \"$d/brightness\" && break; done"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.backlightPath = this.text.trim()
        }
    }

    // Native change watcher (inotify on the file; its directory watch also
    // re-arms on device recreate). Values are read via brightnessctl below
    // — FileView is purely the trigger.
    FileView {
        id: watch
        path: root.backlightPath
        preload: true
        watchChanges: true
        onLoaded: root.pollProc.running = true // initial read once a device exists
        onFileChanged: root.pollProc.running = true
    }

    Process {
        id: pollProc

        command: ["brightnessctl", "-m", "get"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                // "Device,Class,percent,value" — take the first line.
                const line = this.text.trim().split("\n")[0];
                const parts = line ? line.split(",") : [];
                root.percent = parts.length >= 3 ? (parseInt(parts[2]) || 0) : -1;
            }
        }
    }

    // Safety net for kernels without sysfs inotify support (rare; the
    // watch fires first on modern kernels, making this a no-op re-read).
    Timer {
        id: safety
        interval: 2000
        repeat: true
        running: root.backlightPath !== ""
        onTriggered: pollProc.running = true
    }

    Component.onCompleted: probeProc.running = true
}
