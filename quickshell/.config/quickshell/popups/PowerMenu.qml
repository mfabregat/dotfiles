// popups/PowerMenu.qml — lock / logout / suspend / reboot / shutdown.
// Destructive actions are two-step (click once to arm, again to confirm).
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs

LayerPopup {
    id: root

    implicitWidth: 220
    implicitHeight: popupShell.implicitHeight

    property int armedAction: -1

    PowerRow {
            icon: ""
            label: "Lock"
            onTriggered: Quickshell.execDetached(["quickshell", "ipc", "call", "lock", "lock"])
        }

        PowerRow {
            icon: ""
            label: "Log out"
            actionId: 0
            armText: "Log out again?"
            onTriggered: Quickshell.execDetached(["swaymsg", "exit"])
        }

        PowerRow {
            icon: ""
            label: "Suspend"
            actionId: 1
            armText: "Suspend again?"
            onTriggered: Quickshell.execDetached(["systemctl", "suspend"])
        }

        PowerRow {
            icon: ""
            label: "Reboot"
            actionId: 2
            armText: "Reboot again?"
            onTriggered: Quickshell.execDetached(["systemctl", "reboot"])
        }

        PowerRow {
            icon: ""
            label: "Shut down"
            actionId: 3
            armText: "Shut down again?"
            onTriggered: Quickshell.execDetached(["systemctl", "poweroff"])
        }

    // ── Row with two-step confirm ───────────────────────────────────────
    component PowerRow: Rectangle {
        id: row

        property string icon: ""
        property string label: ""
        property int actionId: -1
        property string armText: ""
        signal triggered

        width: parent.width
        height: 34
        radius: 6
        color: rowArea.containsMouse ? Theme.bgHover : "transparent"

        readonly property bool armed: root.armedAction === actionId

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: row.icon
            color: armed ? Theme.brightYellow : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 13
        }

        Text {
            anchors.centerIn: parent
            text: armed ? row.armText : row.label
            color: armed ? Theme.brightYellow : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 12
        }

        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                if (row.actionId >= 0 && !row.armed) {
                    root.armedAction = row.actionId;
                    armTimer.restart();
                    return;
                }
                root.armedAction = -1;
                armTimer.stop();
                row.triggered();
                root.hide();
            }
        }
    }

    Timer {
        id: armTimer
        interval: 3000
        repeat: false
        onTriggered: root.armedAction = -1
    }
}
