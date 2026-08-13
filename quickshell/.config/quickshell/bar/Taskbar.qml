// bar/Taskbar.qml — open windows on this monitor, from the native
// wlr-foreign-toplevel protocol (no swaymsg subprocesses).
// Click: activate · middle click: close (protocol requests).
import Quickshell
import Quickshell.I3
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs

Column {
    id: root

    required property var screen
    // Same tracked lookup as Workspaces.qml (see comment there)
    readonly property var monitor: I3.monitors.values.length ? I3.monitorFor(screen) : null

    spacing: 2

    Repeater {
        model: ToplevelManager.toplevels

        delegate: Rectangle {
            required property var modelData
            readonly property bool mine: modelData.screens.includes(root.monitor)

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
                 : modelData.activated ? Theme.dark1
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
                color: modelData.activated ? Theme.fg : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.bold: true
            }

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                visible: mine
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton

                onClicked: (mouse) => {
                    if (mouse.button === Qt.LeftButton)
                        modelData.activate();
                }
                onPressed: (mouse) => {
                    if (mouse.button === Qt.MiddleButton)
                        modelData.close();
                }
            }
        }
    }
}
