// services/Wallpaper.qml — the wallpaper image the lock screen blurs.
// The sway config paints the same image (`output * bg ../wallpaper.jpg` in
// config.d/output, relative to ~/.config/sway), so the lock screen's blurred
// background matches the desktop exactly — no screencopy, no capture races
// (plan: wallpaper blur).
//
// One-time probe (runs on first use — the LockSurface's Image binding
// instantiates this singleton lazily at the first lock): QML cannot expand
// $HOME and has no native file-exists check, so the probe is a single `sh`
// builtin test — the same availability-probe pattern Brightness uses for
// /sys/class/backlight (no optional binaries). No periodic spawns. If the
// file is missing, `url` stays "" and the lock surface shows its solid
// gruvbox base (the Image simply fails to load).
pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    /// file:// URL of the wallpaper image ("" when none found).
    readonly property string url: root.path.length > 0 ? "file://" + root.path : ""
    property string path: ""

    Process {
        id: probe

        command: ["sh", "-c", "[ -r \"$HOME/.config/sway/wallpaper.jpg\" ] && echo \"$HOME/.config/sway/wallpaper.jpg\""]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.trim();
                if (p.length > 0) root.path = p;
                console.log("[wallpaper] path: " + (root.path.length > 0 ? root.path : "(none)"));
            }
        }
    }

    Component.onCompleted: probe.running = true
}
