// bar/PowerWidget.qml — power menu trigger.
import QtQuick
import qs

Rectangle {
    id: root

    required property var powerMenu

    width: 30
    height: 30
    radius: 7
    color: area.containsMouse ? Theme.bgHover : "transparent"

    Text {
        anchors.centerIn: parent
        text: ""
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: 14
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.powerMenu.showAt(root)
    }
}
