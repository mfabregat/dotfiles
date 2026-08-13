// services/CpuMemTemp.qml — CPU %, memory % and CPU temperature poller.
// Reads /proc/stat, /proc/meminfo and the first hwmon temp sensor every second.
pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property real cpu: 0
    property real mem: 0
    property real temp: 0
    property bool available: false

    property int prevTotal: 0
    property int prevIdle: 0

    // ── Polling ────────────────────────────────────────────────────────
    Process {
        id: pollProc

        command: [
            "sh", "-c",
            "head -1 /proc/stat; awk '/MemTotal|MemAvailable/ {print $2}' /proc/meminfo; cat /sys/class/hwmon/hwmon1/temp1_input 2>/dev/null || echo 0"
        ]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.parse(this.text)
        }
    }

    Process {
        id: checker

        command: ["sh", "-c", "test -r /proc/stat && echo ok"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.available = this.text.trim() === "ok"
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: pollProc.running = true
    }

    Component.onCompleted: checker.running = true

    // ── Parsing ────────────────────────────────────────────────────────
    // Output lines: [0] cpu line, [1] MemTotal kB, [2] MemAvailable kB, [3] temp millideg
    function parse(text: string): void {
        const lines = text.trim().split("\n");
        if (lines.length < 4) return;

        // CPU: "cpu  user nice system idle iowait irq softirq steal guest guest_nice"
        const cpuParts = lines[0].trim().split(/\s+/);
        if (cpuParts.length < 5 || cpuParts[0] !== "cpu") return;

        let total = 0;
        for (let i = 1; i < cpuParts.length; i++) total += parseInt(cpuParts[i]) || 0;
        const idle = (parseInt(cpuParts[4]) || 0) + (parseInt(cpuParts[5]) || 0);

        if (root.prevTotal > 0 && total > root.prevTotal) {
            const dTotal = total - root.prevTotal;
            const dIdle = idle - root.prevIdle;
            root.cpu = Math.min(100, Math.max(0, (1 - dIdle / dTotal) * 100));
        }
        root.prevTotal = total;
        root.prevIdle = idle;

        // Memory (kB): one value per line
        const memTotal = parseInt(lines[1]) || 0;
        const memAvail = parseInt(lines[2]) || 0;
        if (memTotal > 0) root.mem = Math.min(100, Math.max(0, (1 - memAvail / memTotal) * 100));

        // Temperature (millidegrees)
        root.temp = (parseInt(lines[3].trim()) || 0) / 1000;
    }
}
