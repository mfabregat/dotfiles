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
    // One `cat` per tick (sh + cat = 2 forks) instead of the old pipeline
    // (sh + grep + awk + N×cat + sort + tail ≈ 10 forks/s with 6 sensors).
    // The parser below splits the concatenated streams: /proc/stat lines,
    // the MemTotal/MemAvailable lines, and raw hwmon millidegrees.
    Process {
        id: pollProc

        command: [
            "sh", "-c",
            "cat /proc/stat /proc/meminfo /sys/class/hwmon/hwmon*/temp*_input 2>/dev/null"
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
    // then raw hwmon millidegrees (one per line). The hottest sensor wins
    // (machine-agnostic — no per-machine hwmon path).
    function parse(text: string): void {
        const lines = text.trim().split("\n");
        const nums = [];     // MemTotal, MemAvailable
        const temps = [];    // hwmon raw millidegrees
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
            } else if (/^Mem(?:Total|Available):\s*\d+/.test(trimmed)) {
                const m = trimmed.match(/\d+/);
                if (m) nums.push(parseInt(m[0]) || 0);
            } else if (/^\d+$/.test(trimmed)) {
                temps.push(parseInt(trimmed) || 0);
            }
        }

        root.cores = coreList;
        if (nums.length >= 2) {
            const memTotal = nums[0];
            const memAvail = nums[1];
            if (memTotal > 0) {
                root.mem = Math.min(100, Math.max(0, (1 - memAvail / memTotal) * 100));
            }
        }
        if (temps.length > 0) {
            root.temp = Math.max(...temps) / 1000;
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
