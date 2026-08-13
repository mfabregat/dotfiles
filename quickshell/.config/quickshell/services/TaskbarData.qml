// services/TaskbarData.qml — window list for the taskbar, parsed from
// `swaymsg -t get_tree` (sway 1.12's get_workspaces no longer carries nodes).
//
// Refreshed on IPC events (workspace/window/urgent/mode) and when the
// workspace model changes. Each entry carries the output name so
// per-monitor bars can filter.
pragma Singleton

import Quickshell
import Quickshell.I3
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property var windows: [] // [{ monitor, appId, title, conId, focused, urgent, workspace }]

    // Backup trigger: re-render whenever the workspace model itself changes
    property var wsTracker: I3.workspaces.values
    onWsTrackerChanged: root.rebuildSoon()

    I3IpcListener {
        subscriptions: ["workspace", "window", "urgent", "mode"]
        onIpcEvent: () => root.rebuildSoon()
    }

    Timer {
        id: debounce
        interval: 150
        repeat: false
        onTriggered: treeProc.running = true
    }

    Process {
        id: treeProc

        command: ["swaymsg", "-t", "get_tree"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: root.parseTree(this.text)
        }
    }

    function rebuildSoon(): void {
        debounce.restart();
    }

    function parseTree(text: string): void {
        let tree;
        try {
            tree = JSON.parse(text);
        } catch (e) {
            return;
        }
        if (!tree || !tree.nodes) return;

        const list = [];
        for (const out of tree.nodes) {
            if (!out || out.type !== "output") continue;
            for (const ws of out.nodes) {
                if (!ws || ws.type !== "workspace" || ws.name === "__i3_scratch") continue;
                root.walk(ws.nodes, out.name, ws.name, list);
                root.walk(ws.floating_nodes, out.name, ws.name, list);
            }
        }
        root.windows = list;
    }

    function walk(nodes: var, monitor: string, wsName: string, list: var): void {
        for (const n of nodes) {
            if (!n) continue;
            const isWindow = (n.window !== null && n.window !== undefined)
                          || (n.app_id !== null && n.app_id !== undefined);
            if (isWindow && n.type === "con") {
                list.push({
                    monitor: monitor,
                    appId: n.app_id || "",
                    title: n.name || "",
                    conId: n.id || 0,
                    focused: !!n.focused,
                    urgent: !!n.urgent,
                    workspace: wsName,
                });
            } else {
                if (n.nodes) root.walk(n.nodes, monitor, wsName, list);
                if (n.floating_nodes) root.walk(n.floating_nodes, monitor, wsName, list);
            }
        }
    }

    Component.onCompleted: root.rebuildSoon()
}
