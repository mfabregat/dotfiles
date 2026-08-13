// bar/CpuMemWidget.qml — CPU / memory / temperature status icons.
// Colors shift by state (warn -> yellow, critical -> red) like the old bar.
// Temperature thresholds match the old waybar (60/80: hwmon1 is the GPU).
import QtQuick
import QtQuick.Layouts
import qs
import qs.services

ColumnLayout {
    id: root

    readonly property real cpu: CpuMemTemp.cpu
    readonly property real mem: CpuMemTemp.mem
    readonly property real temp: CpuMemTemp.temp

    width: 30
    spacing: 2
    visible: CpuMemTemp.available

    function cpuMemColor(value: real): color {
        if (value >= 90) return Theme.urgent;
        if (value >= 70) return Theme.warn;
        return Theme.fgDim;
    }

    function tempColor(value: real): color {
        if (value >= 80) return Theme.urgent;
        if (value >= 60) return Theme.warn;
        return Theme.fgDim;
    }

    StatusIcon {
        glyph: ""
        value: cpu
        color: cpuMemColor(cpu)
    }
    StatusIcon {
        glyph: ""
        value: mem
        color: cpuMemColor(mem)
    }
    StatusIcon {
        glyph: ""
        value: temp
        color: tempColor(temp)
    }

    component StatusIcon: Column {
        id: item

        property string glyph: ""
        property real value: 0
        property color color: Theme.fgDim

        width: 30
        spacing: 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: item.glyph
            color: item.color
            font.family: Theme.fontFamily
            font.pixelSize: 13
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Math.round(item.value) + "%"
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: 8
        }
    }
}
