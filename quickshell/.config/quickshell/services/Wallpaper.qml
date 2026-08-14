// services/Wallpaper.qml — the wallpaper image the lock screen blurs.
// The sway config paints the same image (`output * bg ../wallpaper.jpg` in
// config.d/output), so the lock screen's blurred background matches the
// desktop exactly — no screencopy, no capture races (plan: wallpaper blur).
//
// The path is probed once at startup (Process pattern, like Brightness):
// the first existing candidate wins. No periodic spawns. `url` is the
// file:// form QML Image sources need; `path` is the plain absolute path.
pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    /// Absolute path of the wallpaper image ("" when none found).
    property string path: ""
    /// file:// URL for QML Image sources ("" when none found).
    readonly property string url: root.path.length > 0 ? "file://" + root.path : ""

    Process {
        id: probe

        command: ["sh", "-c",
            "for p in \"$HOME/.config/sway/wallpaper.jpg\" \"$HOME/.config/sway/wallpaper.png\"; do "
            + "[ -r \"$p\" ] && { echo \"$p\"; break; }; done"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const p = this.text.trim();
                if (p.length > 0) root.path = p;
                console.log("[wallpaper] path: " + (root.path.length > 0 ? root.path : "(none)"));
            }
        }
    }

    Component.onCompleted: {
        console.log("[wallpaper] singleton instantiated");
        probe.running = true;
    }
}
