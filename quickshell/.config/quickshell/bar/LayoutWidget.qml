// bar/LayoutWidget.qml — active keyboard layout; click to switch.
import Quickshell
import Quickshell.I3
import QtQuick
import qs
import qs.services

Rectangle {
    id: root

    width: 30
    height: 22
    radius: 7
    color: area.containsMouse ? Theme.bgHover : "transparent"
    visible: KeyboardLayout.available

    Text {
        anchors.centerIn: parent
        text: KeyboardLayout.layout
        color: Theme.fgDim
        font.family: Theme.fontFamily
        font.pixelSize: 10
        font.bold: true
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: I3.dispatch("input type:keyboard xkb_switch_layout next")
    }
}
