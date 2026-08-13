// bar/PowerWidget.qml — power menu trigger.
import QtQuick
import qs
import qs.services

Rectangle {
    id: root

    required property var screen

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
        onClicked: {
            const menu = PopupRegistry.find(root.screen, "power");
            if (menu) menu.showAt(root.mapToGlobal(0, 0).y);
        }
    }
}
