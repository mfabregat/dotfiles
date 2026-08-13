// services/Brightness.qml — backlight brightness. percent is -1 when no
// backlight is available (widget hides itself).
//
// Phase 5: availability requires a real `backlight`-class device (probe of
// /sys/class/backlight — never trust brightnessctl's default-device
// selection, which falls back to keyboard LEDs and lit up a phantom 0%
// widget on this desktop).
//
// Phase 5.1 (efficiency/portability review): reads are fully native. A
// FileView watches the device's brightness file (inotify on sysfs —
// verified working on kernel 7.1.8 with a throwaway config + raw inotify
// test), and percent is computed from the raw file contents vs the
// device's max_brightness. No brightnessctl subprocess is needed to read
// (text() on a sysfs file is a microsecond blocking read), so the shell
// works on machines where brightnessctl isn't installed. The old 2s
// brightnessctl safety poll is gone: it was 0.5 spawn/s forever guarding
// an unverified "sysfs inotify is inert" failure mode. The bar widget
// still uses brightnessctl to *write* (udev permissions).
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
    /// max_brightness of the same device (static).
    readonly property string maxPath: root.backlightPath.length > 0
        ? root.backlightPath.replace(/\/brightness$/, "/max_brightness") : ""

    Process {
        id: probeProc

        command: ["sh", "-c", "for d in /sys/class/backlight/*; do [ -r \"$d/brightness\" ] && echo \"$d/brightness\" && break; done"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.backlightPath = this.text.trim()
        }
    }

    // Native change watcher: inotify on the brightness file. preload loads
    // once asynchronously; onLoaded covers the initial value without
    // depending on inotify (first reading is never late).
    //
    // IMPORTANT (verified 2026-08-13 with a throwaway config): the watcher
    // does NOT refresh the internal buffer on fileChanged — text() would
    // return the stale cached value. Call reload() on fileChanged and read
    // the fresh value from the internalTextChanged/loaded signals (both
    // fire after the async re-read; updates are idempotent).
    FileView {
        id: watch
        path: root.backlightPath
        preload: true
        watchChanges: true
        onLoaded: root.update()
        onFileChanged: watch.reload()
        onInternalTextChanged: root.update()
    }

    // Static device max — read once (the buffer never changes after the
    // initial preload; text() returns it on demand).
    FileView {
        id: maxView
        path: root.maxPath
        preload: true
        onLoaded: root.update()
    }

    function update(): void {
        if (root.backlightPath === "") return;
        const raw = parseInt(String(watch.text()).trim(), 10);
        const max = parseInt(String(maxView.text()).trim(), 10);
        root.percent = max > 0 && !isNaN(raw)
            ? Math.max(0, Math.min(100, Math.round(100 * raw / max))) : -1;
    }

    Component.onCompleted: probeProc.running = true
}
