// services/LauncherState.qml — global launcher state + IPC entry point.
// sway binds $mod+d to `quickshell ipc call launcher toggle`; each
// screen's Launcher window binds its visibility to `open` (plus being the
// focused monitor). One singleton so the toggle lands exactly once.
pragma Singleton

import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool open: false

    IpcHandler {
        target: "launcher"

        function toggle(): void { root.open = !root.open; }
        function open(): void { root.open = true; }
        function close(): void { root.open = false; }
    }
}
