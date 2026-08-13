// popups/CpuMemPopup.qml — system status details (CPU / MEM / TEMP).
// Data comes from the existing CpuMemTemp poller (1s, shared with the
// glyphs) — this popup adds zero polling. Hover-driven: no input grab;
// closes when the pointer leaves it.
import Quickshell
import QtQuick
import QtQuick.Layouts
import qs
import qs.services

AnchoredPopup {
    id: root

    grabOnOpen: false // hover-driven — must not grab input

    readonly property bool hovered: hoverArea.containsMouse

    implicitWidth: 190
    implicitHeight: popupShell.implicitHeight

    PopupShell {
        id: popupShell
        anchors.fill: parent

        Text {
            text: "System"
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        StatRow {
            glyph: ""
            label: "CPU"
            percent: CpuMemTemp.cpu
            barColor: root.colorFor(CpuMemTemp.cpu)
        }
        StatRow {
            glyph: ""
            label: "MEM"
            percent: CpuMemTemp.mem
            barColor: root.colorFor(CpuMemTemp.mem)
        }
        StatRow {
            glyph: ""
            label: "TEMP"
            percent: Math.min(100, CpuMemTemp.temp)
            valueText: Math.round(CpuMemTemp.temp) + "°C"
            barColor: root.tempColorFor(CpuMemTemp.temp)
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        onExited: root.hide()
    }

    function colorFor(value: real): color {
        if (value >= 90) return Theme.urgent;
        if (value >= 70) return Theme.warn;
        return Theme.accent;
    }

    function tempColorFor(value: real): color {
        if (value >= 80) return Theme.urgent;
        if (value >= 60) return Theme.warn;
        return Theme.accent;
    }

    component StatRow: RowLayout {
        id: row

        property string glyph: ""
        property string label: ""
        property real percent: 0
        property string valueText: Math.round(percent) + "%"
        property color barColor: Theme.accent

        Layout.fillWidth: true
        height: 20
        spacing: 6

        Text {
            text: row.glyph
            color: row.barColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLarge
        }

        Text {
            text: row.label
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            Layout.preferredWidth: 32
        }

        Rectangle {
            Layout.fillWidth: true
            height: 4
            radius: 2
            color: Theme.dark2

            Rectangle {
                width: parent.width * Math.min(100, Math.max(0, row.percent)) / 100
                height: parent.height
                radius: 2
                color: row.barColor
            }
        }

        Text {
            text: row.valueText
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }
    }
}
