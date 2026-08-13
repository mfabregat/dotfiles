// bar/Workspaces.qml — desk pills for the bar's monitor (I3 workspaces).
// Desks are sway-side ("1a", "1b", ...); each monitor shows its own pills.
import Quickshell
import Quickshell.I3
import QtQuick
import QtQuick.Layouts
import qs
import qs.popups

Column {
    id: root

    required property var screen
    // The I3.monitors.values guard makes the binding track valuesChanged,
    // so the lookup re-runs once sway IPC connects. (I3.monitorFor is a
    // native C++ method — its internals aren't tracked by bindings; the
    // guard is what re-triggers it. QML JS function calls ARE tracked.)
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
                onPressed: PopupManager.hideOpen()
                onClicked: modelData.activate()
            }
        }
    }
}
