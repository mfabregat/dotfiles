// services/KeyboardLayout.qml — active xkb layout via sway IPC.
pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property string layout: ""      // short form, e.g. "US" or "ES"
    readonly property bool available: layout !== ""

    Process {
        id: pollProc

        command: ["swaymsg", "-t", "get_inputs"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.parse(this.text)
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: pollProc.running = true
    }

    function parse(text: string): void {
        let inputs;
        try {
            inputs = JSON.parse(text);
        } catch (e) {
            return;
        }
        if (!Array.isArray(inputs)) return;

        for (const input of inputs) {
            if (input.type !== "keyboard") continue;
            const name = input.xkb_active_layout_name || "";
            if (!name) continue;
            // "English (US)" -> "US"; "Spanish" -> "ES"
            const paren = name.match(/\(([^)]+)\)/);
            root.layout = paren ? paren[1].toUpperCase().slice(0, 3)
                                : name.trim().slice(0, 3).toUpperCase();
            return;
        }
    }
}
