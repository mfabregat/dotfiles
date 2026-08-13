// bar/RightBar.qml — vertical bar attached to the right edge.
// Phase 1: shell placeholder; real widgets land in phase 2.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs // shell root: Theme singleton

PanelWindow {
    id: root

    anchors {
        top: true
        bottom: true
        right: true
    }

    implicitWidth: Theme.barWidth
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        anchors.margins: Theme.spacing
        radius: Theme.radius
        color: Theme.bg

        Text {
            anchors.centerIn: parent
            text: "" // nerd font monitor glyph
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize
        }
    }
}
