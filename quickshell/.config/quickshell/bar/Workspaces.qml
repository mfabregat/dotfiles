// bar/Workspaces.qml — desk pills for the bar's monitor (I3 workspaces).
// Desks are sway-side ("1a", "1b", ...); each monitor shows its own pills.
import Quickshell
import Quickshell.I3
import QtQuick
import QtQuick.Layouts
import qs

Column {
    id: root

    required property var screen
    // Tracked through I3.monitors.values so the lookup re-runs once sway IPC
    // connects (a bare function call in a binding would evaluate once, to null).
    readonly property var monitor: I3.monitors.values.length ? I3.monitorFor(screen) : null

    spacing: 2

    Repeater {
        model: I3.workspaces

        delegate: Rectangle {
            required property var modelData
            readonly property bool mine: modelData.monitor === root.monitor
            readonly property bool focused: mine && modelData.focused

            width: Theme.pillWidth
            height: mine ? Theme.pillHeight : 0
            visible: mine
            radius: 6
            color: pillArea.containsMouse && mine ? Theme.bgHover
                 : focused ? Theme.accent
                 : modelData.urgent && mine ? Theme.brightRed
                 : Theme.dark1

            Text {
                anchors.centerIn: parent
                text: modelData.number
                color: focused || (modelData.urgent && mine) ? Theme.dark0 : Theme.fgDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            MouseArea {
                id: pillArea
                anchors.fill: parent
                hoverEnabled: true
                visible: root.monitor !== null
                onClicked: modelData.activate()
            }
        }
    }
}
