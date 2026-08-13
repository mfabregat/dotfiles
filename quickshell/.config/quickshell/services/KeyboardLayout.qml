// services/KeyboardLayout.qml — active xkb layout, from sway IPC input
// events (no polling): one initial read, then compositor pushes changes.
pragma Singleton

import Quickshell
import Quickshell.I3
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string layout: ""      // short form, e.g. "US" or "ES"
    readonly property bool available: layout !== ""

    // Initial state (input events only arrive on change)
    Process {
        id: initialProc

        command: ["swaymsg", "-t", "get_inputs"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parse(this.text)
        }
    }

    I3IpcListener {
        subscriptions: ["input"]
        onIpcEvent: (event) => root.parse(event.data)
    }

    function parse(text: string): void {
        let obj;
        try {
            obj = JSON.parse(text);
        } catch (e) {
            return;
        }
        // get_inputs returns an array; input events carry a single device
        const inputs = Array.isArray(obj) ? obj : [obj];
        for (const input of inputs) {
            if (!input || input.type !== "keyboard") continue;
            const name = input.xkb_active_layout_name || "";
            if (!name) continue;
            // "English (US)" -> "US"; "Spanish" -> "ES"
            const paren = name.match(/\(([^)]+)\)/);
            root.layout = paren ? paren[1].toUpperCase().slice(0, 3)
                                : name.trim().slice(0, 3).toUpperCase();
            return;
        }
    }

    Component.onCompleted: initialProc.running = true
}
