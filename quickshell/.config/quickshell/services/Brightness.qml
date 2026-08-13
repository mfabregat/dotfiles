// services/Brightness.qml — backlight brightness poller (brightnessctl).
// percent is -1 when no backlight is available (widget hides itself).
pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property int percent: -1
    readonly property bool available: percent >= 0

    Process {
        id: pollProc

        command: ["brightnessctl", "-m", "get"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                // "Device,Class,percent,value"
                const parts = this.text.trim().split(",");
                root.percent = parts.length >= 3 ? (parseInt(parts[2]) || 0) : -1;
            }
        }
    }

    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: pollProc.running = true
    }
}
