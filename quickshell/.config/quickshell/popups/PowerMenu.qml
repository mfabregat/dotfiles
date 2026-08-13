// popups/PowerMenu.qml — lock / logout / suspend / reboot / shutdown.
// Destructive actions are two-step (click once to arm, again to confirm).
// Layout: micro-label section header, rows grouped with a divider between
// safe and destructive actions.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs

AnchoredPopup {
    id: root

    implicitWidth: 230
    implicitHeight: popupShell.implicitHeight

    property int armedAction: -1

    PopupShell {
        id: popupShell
        anchors.fill: parent

        SectionLabel { text: "Power" }

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

        Divider {}

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
    }

    // ── Section header (small caps micro-label) ────────────────────────
    component SectionLabel: Text {
        text: ""
        color: Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        font.bold: true
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Theme.letterSpacing
    }

    component Divider: Rectangle {
        width: parent.width
        height: 1
        color: Theme.dark2
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
        height: Theme.popupRowHeight
        radius: Theme.radius
        color: rowArea.containsMouse ? Theme.bgHover : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }

        readonly property bool armed: root.armedAction === actionId

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: row.icon
            color: armed ? Theme.warn : Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeGlyphs
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 36
            anchors.verticalCenter: parent.verticalCenter
            text: armed ? row.armText : row.label
            color: armed ? Theme.warn : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            Behavior on color { ColorAnimation { duration: 150 } }
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
                root.visible = false;
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
