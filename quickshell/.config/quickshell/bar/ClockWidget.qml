// bar/ClockWidget.qml — HH:MM clock; click opens the calendar popup.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs

Rectangle {
    id: root

    required property var calendar

    width: Theme.widgetWidth
    height: 42  // 2 × 19.1px lines @ 14pt + 2×2 margins
    radius: 7
    color: area.containsMouse ? Theme.bgHover : "transparent"

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 2
        spacing: 0

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(clock.date, "HH")
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(clock.date, "mm")
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            font.bold: true
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.calendar.showAt(root)
    }
}
