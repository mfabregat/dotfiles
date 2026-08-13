// bar/BacklightWidget.qml — screen brightness (brightnessctl).
// Left click: cycle 5 steps · scroll: ±5%.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs
import qs.services

Rectangle {
    id: root

    readonly property int percent: Brightness.percent

    width: 30
    height: 36
    radius: 7
    color: area.containsMouse ? Theme.bgHover : "transparent"
    visible: Brightness.available

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 2
        spacing: 0

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: ""
            color: percent < 40 ? Theme.fgDim : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: 14
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: percent >= 0 ? percent + "%" : ""
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: 9
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true

        onWheel: (wheel) => {
            const dir = wheel.angleDelta.y > 0 ? "+" : "-";
            Quickshell.execDetached(["brightnessctl", "set", "5%" + dir]);
        }
        onClicked: Quickshell.execDetached(["brightnessctl", "set", "5%-"])
    }
}
