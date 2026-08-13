// bar/Taskbar.qml — open windows on this monitor (icons; click to focus,
// middle click to close). Data comes from services/TaskbarData.qml.
import Quickshell
import Quickshell.I3
import QtQuick
import QtQuick.Layouts
import qs
import qs.services

Column {
    id: root

    required property var screen
    // Same tracked lookup as Workspaces.qml (see comment there)
    readonly property var monitor: I3.monitors.values.length ? I3.monitorFor(screen) : null
    readonly property string monitorName: monitor ? monitor.name : ""

    spacing: 2

    Repeater {
        model: TaskbarData.windows

        delegate: Rectangle {
            required property var modelData
            readonly property bool mine: modelData.monitor === root.monitorName

            // Resolve the real icon name via the app's desktop entry.
            // The applications list is passed in so the binding re-evaluates
            // once the (async) desktop entry scan completes.
            readonly property var entry: findEntry(modelData.appId, DesktopEntries.applications.values)
            readonly property string iconName: entry && entry.icon ? entry.icon : (modelData.appId || "")

            function findEntry(appId: string, apps: var): var {
                if (!appId) return null;
                for (const a of apps) if (a.id === appId) return a;
                const lower = appId.toLowerCase();
                for (const a of apps)
                    if (a.id.toLowerCase().includes(lower) || lower.includes(a.id.toLowerCase())) return a;
                return null;
            }

            width: 28
            height: mine ? 28 : 0
            visible: mine
            radius: 6
            color: area.containsMouse ? Theme.bgHover
                 : modelData.focused ? Theme.dark1
                 : modelData.urgent ? Theme.brightRed
                 : "transparent"

            Image {
                id: icon
                anchors.centerIn: parent
                width: 16
                height: 16
                source: mine ? "image://icon/" + iconName : ""
                sourceSize { width: 16; height: 16 }
                visible: status === Image.Ready
            }

            Text {
                anchors.centerIn: parent
                visible: !icon.visible && mine
                text: modelData.appId ? modelData.appId.charAt(0).toUpperCase() : "?"
                color: modelData.focused ? Theme.fg : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.bold: true
            }

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                visible: mine
                onClicked: I3.dispatch(`[con_id=${modelData.conId}] focus`)
                onPressed: (mouse) => {
                    if (mouse.button === Qt.MiddleButton)
                        I3.dispatch(`[con_id=${modelData.conId}] kill`)
                }
            }
        }
    }
}
