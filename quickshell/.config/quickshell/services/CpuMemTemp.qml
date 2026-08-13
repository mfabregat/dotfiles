// services/CpuMemTemp.qml — CPU (total + per-core) %, memory %, hottest
// temperature, and short histories. One small process per second; the
// values feed both the bar glyphs and the details popup.
pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property real cpu: 0
    property real mem: 0
    property real temp: 0
    property var cores: []          // per-core usage %
    property var cpuHistory: []     // last samples (sparkline)
    property var memHistory: []
    property string cpuName: ""     // read once at startup
    property bool available: false

    readonly property int historyLen: 40
    property var prevStats: ({})

    // ── Polling ────────────────────────────────────────────────────────
    Process {
        id: pollProc

        command: [
            "sh", "-c",
            "grep '^cpu' /proc/stat; awk '/MemTotal|MemAvailable/ {print $2}' /proc/meminfo;"
            + " for f in /sys/class/hwmon/hwmon*/temp*_input; do cat \"$f\"; done | sort -n | tail -1"
        ]
        running: true

        stdout: StdioCollector {
            onStreamFinished: root.parse(this.text)
        }
    }

    // CPU model name, once (for the details popup header)
    Process {
        id: nameProc

        command: ["sh", "-c", "grep -m1 'model name' /proc/cpuinfo | sed 's/.*: //; s/  */ /g'"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.cpuName = this.text.trim()
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

    Component.onCompleted: {
        checker.running = true;
        nameProc.running = true;
    }

    // ── Parsing ────────────────────────────────────────────────────────
    // Output: "cpu ..." + "cpuN ..." lines, then MemTotal/MemAvailable,
    // then the hottest hwmon temperature (millidegrees).
    function parse(text: string): void {
        const lines = text.trim().split("\n");
        const nums = [];
        const coreList = [];

        for (const line of lines) {
            const trimmed = line.trim();
            if (trimmed.startsWith("cpu")) {
                const parts = trimmed.split(/\s+/);
                if (parts.length < 5) continue;
                let total = 0;
                for (let i = 1; i < parts.length; i++) total += parseInt(parts[i]) || 0;
                const idle = (parseInt(parts[4]) || 0) + (parseInt(parts[5]) || 0);

                const prev = root.prevStats[parts[0]] || { t: 0, i: 0 };
                let pct = 0;
                if (prev.t > 0 && total > prev.t) {
                    pct = Math.min(100, Math.max(0, (1 - (idle - prev.i) / (total - prev.t)) * 100));
                }
                root.prevStats[parts[0]] = { t: total, i: idle };

                if (parts[0] === "cpu") root.cpu = pct;
                else coreList.push(pct);
            } else if (/^\d+$/.test(trimmed)) {
                nums.push(parseInt(trimmed) || 0);
            }
        }

        root.cores = coreList;
        if (nums.length >= 3) {
            const memTotal = nums[0];
            const memAvail = nums[1];
            if (memTotal > 0) {
                root.mem = Math.min(100, Math.max(0, (1 - memAvail / memTotal) * 100));
            }
            root.temp = nums[2] / 1000;
        }

        // History (sparklines): keep the last `historyLen` samples
        root.cpuHistory = pushHistory(root.cpuHistory, root.cpu);
        root.memHistory = pushHistory(root.memHistory, root.mem);
    }

    function pushHistory(hist: var, value: real): var {
        const h = hist ? hist.slice() : [];
        h.push(value);
        if (h.length > root.historyLen) h.shift();
        return h;
    }
}
