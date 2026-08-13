// bar/BatteryWidget.qml — battery percent + charging state (UPower).
import Quickshell
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import qs

Rectangle {
    id: root

    readonly property var battery: UPower.displayDevice
    readonly property int percent: battery && battery.ready ? Math.round(battery.percent) : -1
    readonly property bool charging: battery && battery.state === UPowerDeviceState.Charging
    readonly property bool plugged: battery && battery.state === UPowerDeviceState.FullyCharged
    readonly property bool discharging: battery && battery.state === UPowerDeviceState.Discharging

    width: Theme.widgetWidth
    height: 27
    radius: 7
    color: area.containsMouse ? Theme.bgHover : "transparent"
    // Hide phantom batteries (desktops: DisplayDevice reports 0%, not on battery)
    visible: percent > 0 || UPower.onBattery

    function batteryIcon(): string {
        if (charging || plugged) return "";
        if (percent >= 90) return "";
        if (percent >= 65) return "";
        if (percent >= 40) return "";
        if (percent >= 15) return "";
        return "";
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 2
        spacing: 0

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.batteryIcon()
            color: percent <= 15 && discharging ? Theme.urgent
                 : percent <= 30 && discharging ? Theme.warn
                 : Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeLarge
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: percent + "%"
            color: Theme.fgDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeTiny
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
    }
}
