// bar/BacklightWidget.qml — screen brightness (brightnessctl).
// Click: brightness popup (slider) · scroll: ±5%.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs
import qs.popups
import qs.services

Rectangle {
    id: root

    required property var backlightPopup

    readonly property int percent: Brightness.percent

    width: Theme.widgetWidth
    height: 27
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
            font.pixelSize: Theme.fontSizeGlyphs
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: percent >= 0 ? percent + "%" : ""
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.backlightPopup.showAt(root)

        onWheel: (wheel) => {
            const dir = wheel.angleDelta.y > 0 ? "+" : "-";
            Quickshell.execDetached(["brightnessctl", "set", "5%" + dir]);
        }
    }
}
