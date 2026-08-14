// services/ControlCenter.qml — control center state + IPC entry point.
// sway binds $mod+Shift+c to `quickshell ipc call controlcenter toggle`;
// each screen's window (popups/ControlCenter.qml) binds visibility to
// `open` (plus being the focused monitor).
pragma Singleton

import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool open: false

    IpcHandler {
        target: "controlcenter"

        function toggle(): void { root.open = !root.open; }
        function open(): void { root.open = true; }
        function close(): void { root.open = false; }
    }
}
