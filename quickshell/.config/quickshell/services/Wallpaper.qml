// services/Wallpaper.qml — the wallpaper image the lock screen blurs.
// The sway config paints the same image (`output * bg ../wallpaper.jpg` in
// config.d/output, relative to ~/.config/sway), so the lock screen's blurred
// background matches the desktop exactly — no screencopy, no capture races
// (plan: wallpaper blur).
//
// Probe is fully native (2026-08-14 review): $HOME via Quickshell.env, and
// FileView's missing-file behavior as the existence check — a preload on a
// nonexistent path never fires onLoaded and `.loaded` stays false (verified
// with a throwaway config). The old single `sh` builtin probe is gone. If
// the file is missing, `url` stays "" and the lock surface shows its solid
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

    readonly property string candidate: (Quickshell.env("HOME") || "")
        + "/.config/sway/wallpaper.jpg"

    // onLoaded only fires when the preload read succeeds (exists); the
    // missing-file case never fires it (verified 2026-08-14).
    FileView {
        id: wall
        path: root.candidate
        preload: true
        onLoaded: {
            root.path = root.candidate;
            console.log("[wallpaper] path: " + root.path);
        }
    }
}
